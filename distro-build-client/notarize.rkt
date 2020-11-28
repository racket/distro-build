#lang racket/base
(require racket/promise
         racket/system
         racket/match
         racket/file
         racket/string
         "display-time.rkt")

(provide notarize-file
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

;; these could be run in parallel. Wouldn't help during the upload
;; period, but it might parallelize perfectly during the apple-side
;; notarization process, depending on how they allocate their
;; resources. 
(define (notarize-file file
                       #:primary-bundle-id primary-bundle-id
                       #:user user
                       #:app-specific-password app-specific-password
                       #:wait-seconds [wait-seconds 60]
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
  (cond
    [(file-notarized? file)
     (printf/flush "Binary already signed, ignoring this file\n")]
    [else
     (printf/flush "Binary not notarized, so proceeding\n")
     (define (failed why)
       (if error-on-fail?
           (error 'notarize-file "~a" why)
           (printf/flush "~a\n" why)))
     (define (system*/filter exe
                             #:filter filter-rx
                             #:filter-result filter-result
                             #:fail-message why
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
       (unless ok? (failed why))
       result)
     (define request-id
       (system*/filter (force xcrun-path)
                       "altool" "--notarize-app"
                       "-f" file
                       "--primary-bundle-id" primary-bundle-id
                       "-u" user
                       "-p" app-specific-password
                       #:filter #rx"RequestUUID = ([-a-fA-F0-9]+)"
                       #:filter-result (lambda (m) (cadr m))
                       #:fail-message "request upload failed"))

     (when request-id
       (let loop ()
         (printf/flush "Wait ~a seconds\n" wait-seconds)
         (sleep wait-seconds)
         (printf/flush "Ping ~a\n" request-id)
         (define status
           (system*/filter (force xcrun-path)
                           "altool" "--notarization-info" request-id
                           "-u" user
                           "-p" app-specific-password
                           #:filter #rx"Status: (.*)"
                           #:filter-result (lambda (m) (cadr m))
                           #:fail-message "status check failed"))
         (when (equal? status "in progress")
           (loop)))
       
       ;; proceed with stapler even if notarization fails; the failure may
       ;; be simply that the file has already been notarized, but still
       ;; needs to be stapled
       (printf/flush "Stapling file: ~e\n" file)
       (unless (system* (force xcrun-path) "stapler" "staple" file)
         (failed "stapling failed")))])
  (display-time))

(define (notarize-file/config file ht)
  (define (ref sym [default (lambda ()
                              (error 'notarize-file/config "missing key: ~e" sym))])
    (hash-ref ht sym default))
  (notarize-file file
                 #:primary-bundle-id (ref 'primary-bundle-id)
                 #:user (ref 'user)
                 #:app-specific-password (check-password
                                          (string-trim
                                           (file->string
                                            (ref 'app-specific-password-file))))
                 #:wait-seconds (ref 'wait-seconds 60)
                 #:error-on-fail? (ref 'error-on-fail? #t)))

;; sanity check password
(define (check-password password)
  (match password
    ;; not really sure whether digits can occur?
    [(regexp #px"^[-a-z0-9]{3,30}$") (void)]
    [else (error 'password "this doesn't look like a reasonable signing password: ~e"
                 password)])
  password)

(module+ main
  (require racket/cmdline)
  (command-line
   #:args (bundle-path primary-bundle-id user app-specific-password-file)
   (notarize-file/config bundle-path (hash 'primary-bundle-id primary-bundle-id
                                           'user user
                                           'app-specific-password-file app-specific-password-file))))
