#lang racket/base
(require racket/promise
         racket/system
         racket/match
         racket/file
         racket/string
         "display-time.rkt")

(provide notarize-file-via-rcodesign
         notarize-file
         notarize-file/config
         file-notarized?)

;; NB: Notarization is a bit weird; it consists of three steps.
;; 1) the bundle must be signed, using 'codesign'. That doesn't happen
;;    in this file.
;; 2) The bundle must be uploaded to Apple; essentially, the signed
;;    bundle is what in crypto you would think of as a signing-request.
;;    The strange thing is that success does not "return" approval; it
;;    simply registers the approval in Apple's database, and returns
;;    a success notification.
;; 3) Finally, you need to use the "stapler" in order to fetch that
;;    approval and mutate the bundle to contain the approval. This
;;    final bundle can now be distributed to users.

;; Submit the bundle to Apple for notarization:
;; - xcrun altool --notarize-app -f $BUNDLE --primary-bundle-id "org.racket-lang.DrRacket" -u "mflatt@cs.utah.edu" -p $APP_SPECIFIC_KEYWORD
;;   ... returns long id, in our case ada9cd7a-721c-47b9-a4f5-e2943edf540f ( = $NOTARIZATION_ID )
;; If necessary, check the status of notarization using the id returned by the previous step:
;; - xcrun altool --notarization-info $NOTARIZATION_ID -u "mflatt@cs.utah.edu" -p $APP_SPECIFIC_KEYWORD
;; Mutate the bundle to contain the signature. This is weird, you'd expect to have to pass some information
;;  besides the bundle, but that lookup all happens silently:
;; - xcrun stapler staple $BUNDLE
;; again, you shouldn't need to run any of those unless 'gon' breaks.

;; to check whether something is signed, use
;; codesign -v -vvv --test-requirement="=notarized" <bundle>
;; ... this is what the code below does.

;; also, just to have this written down:
;; spctl -a -v <app directory>
;; ... can be used to see whether an app is "acceptable" from a security standpoint

;; helpful side information; upload can fail with
;; "Cannot proceed with delivery: an existing transporter instance is
;; currently uploading this package (-18000)". This problem can maybe indicate
;; that the file is being processed and you should just sit tight, but some
;; posts on Stack Overflow suggest that you might need to delete *.token files
;; from ~/Library/Caches/com.apple.amp.itmstransporter/UploadTokens

;; Number of failures to tolerate in each of the two steps (upload and status checking)
(define NUM-TRIES 3)

;; find the path to the named binary (using the current shell settings).
;; Signal an error if it's not found
(define (find-binary name)
  (or (find-executable-path name)
      (error 'find-binary
             "couldn't find executable: ~e"
             name)))

(define xcrun-path (delay (find-binary "xcrun")))
(define codesign-path (delay (find-binary "codesign")))

;; given a file, is it notarized?
(define (file-notarized? file)
  (define out-str (open-output-string))
  (define err-str (open-output-string))
  (define result
    (parameterize ([current-output-port out-str]
                   [current-error-port err-str])
      (system* (force codesign-path)
                "-v"
                "-vvv"
                "--test-requirement==notarized"
                file)))
  (match (list result (get-output-string out-str) (get-output-string err-str))
    [(list #f
           ""
           (regexp #px"\ntest-requirement: code failed to satisfy specified code requirement"))
     #f]
    [(list #t
           ""
           (regexp #px"explicit requirement satisfied\n$"))
     #t]
    [other (error
            'check-notarization-status
            "unexpected output from codesign: ~e"
            other)]))

(define (printf/flush . args)
  (apply printf args)
  (flush-output))

(define (notarize-file-via-rcodesign file
                                     #:api-key-file api-key-file
                                     #:wait-seconds [wait-seconds 120]
                                     #:error-on-fail? [error-on-fail? #t])
  (printf/flush "Notarize-file-via-rcodesign: ~v\n"
                file)
  (display-time)
  (let request-loop ([tries NUM-TRIES])
    (printf/flush "Upload ~a\n" file)
    (define ok?
      (system* (or (find-executable-path "rcodesign")
                   (error 'notarize-file-via-rcodesign "could not find rcodesign"))
               "notary-submit"
               "--staple"
               "--api-key-file" api-key-file
               "--max-wait-seconds" (format "~a" wait-seconds)
               file))
    (cond
      [ok?
       (printf/flush "Success\n")]
      [(positive? tries)
       (request-loop (sub1 tries))]
      [else
       (if error-on-fail?
           (error 'notarize-file-via-rcodesign "notarization failed")
           (printf/flush "notarization failed\n"))])))

;; these could be run in parallel. Wouldn't help during the upload
;; period, but it might parallelize perfectly during the apple-side
;; notarization process, depending on how they allocate their
;; resources. 
(define (notarize-file file
                       #:primary-bundle-id primary-bundle-id
                       #:user user
                       #:team team
                       #:app-specific-password app-specific-password
                       #:wait-seconds [wait-seconds 120]
                       #:error-on-fail? [error-on-fail? #t])
  (printf/flush "Notarize-file: ~v\n"
                file)
  (display-time)
  (unless (string? file)
    (raise-argument-error 'notarize-file "string" 0 file))
  (when (not (file-exists? file))
    (error 'notarize-file
           "input file does not exist: ~e"
           file))
  (define (failed why)
    (if error-on-fail?
        (error 'notarize-file "~a" why)
        (printf/flush "~a\n" why)))
  (define (xcrun-notarytool cmd)
    (let request-loop ([tries NUM-TRIES])
      (printf/flush "Upload ~a\n" file)
      (define ok?
        (apply system* (append cmd
                               (list "submit"
                                     "--apple-id" user
                                     "--team-id" team
                                     "--password" app-specific-password
                                     "--wait"
                                     "--timeout" (format "~as" wait-seconds)
                                     file))))
      (cond
        [ok?
         (staple)]
        [(positive? tries)
         (request-loop (sub1 tries))]
        [else
         (failed "notarization failed")])))
  (define (staple)
    (printf/flush "Stapling file: ~e\n" file)
    (unless (system* (force xcrun-path) "stapler" "staple" file)
      (failed "stapling failed")))
  (cond
    [(file-notarized? file)
     (printf/flush "Binary already notarized, so skipping\n")]
    [(find-executable-path "notarytool")
     => (lambda (notarytool)
          (printf/flush "Binary not already notarized, so proceeding with notarytool\n")
          (xcrun-notarytool (list notarytool)))]
    [(xcrun-tool-works? "notarytool")
     (printf/flush "Binary not already notarized, so proceeding with xcrun notarytool\n")
     (xcrun-notarytool (list (force xcrun-path) "notarytool"))]
    [else
     ;; Apple is discontinuing `altool` as of 01-NOV-2023, so the following mode
     ;; is unlikely to be useful by the time you read this
     (printf/flush "Binary not already notarized, so proceeding with xcrun altool\n")
     (define (system*/filter exe
                             #:filter filter-rx
                             #:filter-result filter-result
                             #:fail-message [why "failed"]
                             #:fail-k [fail-k #f]
                             #:success-k [success-k (lambda (v) v)]
                             . args)
       (define orig-out (current-output-port))
       (define-values (i o) (make-pipe))
       (define result #f)
       (define t (thread
                  (lambda ()
                    (let loop ()
                      (define l (read-line i))
                      (unless (eof-object? l)
                        (fprintf orig-out "~a\n" l)
                        (flush-output orig-out)
                        (define m (regexp-match filter-rx l))
                        (when m
                          (set! result (filter-result m)))
                        (loop))))))
       (define ok? (parameterize ([current-output-port o])
                     (apply system* exe args)))
       (close-output-port o)
       (thread-wait t)
       (if ok?
           (success-k result)
           (if fail-k
               (fail-k)
               (failed why))))
     (let request-loop ([tries NUM-TRIES])
       (printf/flush "Upload ~a\n" file)
       (system*/filter
        (force xcrun-path)
        "altool" "--notarize-app"
        "-f" file
        "--primary-bundle-id" primary-bundle-id
        "-u" user
        "-p" app-specific-password
        #:filter #rx"RequestUUID = ([-a-fA-F0-9]+)"
        #:filter-result (lambda (m) (cadr m))
        #:fail-message "request upload failed"
        #:fail-k (and (positive? tries)
                      (lambda ()
                        (request-loop (sub1 tries))))
        #:success-k
        (lambda (request-id)
          (when request-id
            (let loop ([tries NUM-TRIES])
              (printf/flush "Wait ~a seconds\n" wait-seconds)
              (sleep wait-seconds)
              (printf/flush "Ping ~a\n" request-id)
              (system*/filter (force xcrun-path)
                              "altool" "--notarization-info" request-id
                              "-u" user
                              "-p" app-specific-password
                              #:filter #rx"Status: (.*)"
                              #:filter-result (lambda (m) (cadr m))
                              #:fail-message "status check failed"
                              #:fail-k (and (positive? tries)
                                            (lambda ()
                                              (loop (sub1 tries))))
                              #:success-k (lambda (status)
                                            (when (equal? status "in progress")
                                              (loop tries)))))
            ;; proceed with stapler even if notarization fails; the failure may
            ;; be simply that the file has already been notarized, but still
            ;; needs to be stapled
            (staple)))))])
  (display-time))

(define (notarize-file/config file ht)
  (define (ref sym [default (lambda ()
                              (error 'notarize-file/config "missing key: ~e" sym))])
    (hash-ref ht sym default))
  (define (file-path file)
    (let ([dir (ref 'app-specific-password-dir #f)])
      (if dir
          (build-path dir file)
          file)))
  (cond
    [(ref 'api-key-file #f)
     => (lambda (api-key-file)
          (notarize-file-via-rcodesign file
                                       #:api-key-file (file-path api-key-file)
                                       #:wait-seconds (ref 'wait-seconds 120)
                                       #:error-on-fail? (ref 'error-on-fail? #t)))]
    [else
     (notarize-file file
                    #:primary-bundle-id (ref 'primary-bundle-id)
                    #:user (ref 'user)
                    #:team (ref 'team)
                    #:app-specific-password (check-password
                                             (string-trim
                                              (file->string
                                               (file-path (ref 'app-specific-password-file)))))
                    #:wait-seconds (ref 'wait-seconds 120)
                    #:error-on-fail? (ref 'error-on-fail? #t))]))

;; sanity check password
(define (check-password password)
  (match password
    ;; not really sure whether digits can occur?
    [(regexp #px"^[-a-z0-9]{3,30}$") (void)]
    [else (error 'password "this doesn't look like a reasonable signing password: ~e"
                 password)])
  password)

(define (xcrun-tool-works? tool)
  (parameterize ([current-output-port (open-output-bytes)]
                 [current-error-port (open-output-bytes)])
    (system* (force xcrun-path) tool)))

(module+ main
  (require racket/cmdline)
  (command-line
   #:args (bundle-path primary-bundle-id user team app-specific-password-file)
   (notarize-file/config bundle-path (hash 'primary-bundle-id primary-bundle-id
                                           'user user
                                           'team team
                                           'app-specific-password-file app-specific-password-file))))
