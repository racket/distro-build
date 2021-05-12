#lang racket/base
(require racket/cmdline
         "installer-sh.rkt"
         "installer-dmg.rkt"
         "installer-pkg.rkt"
         "installer-exe.rkt"
         "installer-tgz.rkt"
         net/url
         racket/file
         racket/path
         racket/port
         racket/string
         racket/system
         net/base64
         setup/cross-system
         "display-time.rkt")

(module test racket/base)

(define release? #f)
(define source? #f)
(define versionless? #f)
(define tgz? #f)
(define mac-pkg? #f)
(define hardened-runtime? #f)
(define notarization-config #f)
(define upload-to #f)
(define upload-desc "")
(define download-readme #f)
(define post-process-cmd #f)
(define pre-process-cmd #f)
(define dist-base-version (version))

(define-values (short-human-name human-name base-name dir-name dist-suffix 
                                 sign-identity osslsigncode-args-base64)
  (command-line
   #:once-each
   [("--release") "Create a release installer"
    (set! release? #t)]
   [("--source") "Create a source installer"
    (set! source? #t)]
   [("--versionless") "Avoid version number in names and paths"
    (set! versionless? #t)]
   [("--tgz") "Create a \".tgz\" archive instead of an installer"
    (set! tgz? #t)]
   [("--mac-pkg") "Create a \".pkg\" installer on Mac OS"
    (set! mac-pkg? #t)]
   [("--packed-options") options ("Additional comma-separated options:"
                                  "  tgz - create a \".tgz\" archive instead of an installer"
                                  "  pkg - create a \".pkg\" installer on Mac OS"
                                  "  hardened - specify hardened runtime for Mac OS signing"
                                  "  version=<vers> - use <vers> in installer names")
    (for ([h (in-list (string-split options #rx","))])
      (case h
        [("tgz") (set! tgz? #t)]
        [("pkg") (set! mac-pkg? #t)]
        [("hardened") (set! hardened-runtime? #t)]
        [else
         (cond
           [(regexp-match #rx"^version=(.*)$" h)
            => (lambda (m) (set! dist-base-version (cadr m)))]
           [else
            (raise-user-error "unrecognized packed option:" h)])]))]
   [("--notarization-config") config-as-base64 "Notarize a Mac OS installer before uploading"
    (set! notarization-config config-as-base64)]
   [("--upload") url "Upload installer"
    (unless (string=? url "")
      (set! upload-to url))]
   [("--desc") desc "Description to accompany upload"
    (set! upload-desc desc)]
   [("--readme") readme "URL for README.txt to include"
    (unless (string=? readme "")
      (set! download-readme readme))]
   [("--pre-process") cmd-as-base64 "Program plus arguments to run on the directory before packaging"
    (unless (string=? cmd-as-base64 "")
      (set! pre-process-cmd cmd-as-base64))]
   [("--post-process") cmd-as-base64 "Program plus arguments to run on the installer before uploading"
    (unless (string=? cmd-as-base64 "")
      (set! post-process-cmd cmd-as-base64))]
   #:args
   (human-name base-name dir-name dist-suffix sign-identity osslsigncode-args-base64)
   (values human-name
           (format "~a v~a" human-name (version))
           (if versionless?
               base-name
               (format "~a-~a" base-name dist-base-version))
           (if (or (and release? (not source?))
                   versionless?)
               dir-name
               (format "~a-~a" dir-name dist-base-version))
           (if (string=? dist-suffix "")
               ""
               (string-append "-" dist-suffix))
           sign-identity osslsigncode-args-base64)))

(display-time)

(define readme
  (and download-readme
       (let ()
         (printf "Downloading ~a\n" download-readme)
         (flush-output)
         (define i (get-pure-port (string->url download-readme)))
         (begin0
          (port->string i)
          (close-input-port i)))))

(define (unpack-base64 str)
  (base64-decode (string->bytes/utf-8 str)))

(define (unpack-base64-strings str)
  (define p (open-input-bytes (unpack-base64 str)))
  (define l (read p))
  (unless (and (list? l)
               (andmap string? l)
               (eof-object? (read p)))
    (error 'unpack-base64-strings
           "encoded arguments didn't decode and `read` as a list of strings: ~e" str))
  l)

(when pre-process-cmd
  (define args (append (unpack-base64-strings pre-process-cmd)
                       (list "bundle/racket")))
  (unless (apply system* args)
    (error 'pre-process "failed for ~s" args)))

(define installer-file
  (if (or source? tgz?)
      (installer-tgz source? base-name dir-name dist-suffix readme)
      (case (cross-system-type)
        [(unix)
         (installer-sh human-name base-name dir-name release? dist-suffix readme)]
        [(macosx)
         (if mac-pkg?
             (installer-pkg (if (or release? versionless?)
                                short-human-name
                                human-name)
                            base-name dist-suffix readme sign-identity)
             (installer-dmg (if versionless?
                                short-human-name
                                human-name)
                            base-name dist-suffix readme
                            sign-identity
                            (and notarization-config
                                 (let ()
                                   (define ht
                                     (with-handlers
                                         ([exn:fail?
                                           (lambda (exn)
                                             (error 'notarization-config "bad encoding: ~s"
                                                    notarization-config))])
                                       (read (open-input-bytes
                                              (unpack-base64 notarization-config)))))
                                   (unless (hash? ht)
                                     (error 'notarization-config "expected hash, got ~e" ht))
                                   ht))
                            #:hardened-runtime? hardened-runtime?))]
        [(windows)
         (define osslsigncode-args
           (and (not (equal? osslsigncode-args-base64 ""))
                (unpack-base64-strings osslsigncode-args-base64)))
         (installer-exe short-human-name base-name (or release? versionless?)
                        dist-suffix readme
                        osslsigncode-args)])))

(when post-process-cmd
  (define args (append (unpack-base64-strings post-process-cmd)
                       (list installer-file)))
  (unless (apply system* args)
    (error 'post-process "failed for ~s" args)))

(call-with-output-file*
 (build-path "bundle" "installer.txt")
 #:exists 'truncate/replace
 (lambda (o) 
   (fprintf o "~a\n" installer-file)
   (fprintf o "~a\n" upload-desc)))

(when upload-to
  (printf "Upload ~a to ~a\n" installer-file upload-to)
  (flush-output)
  (define url (string->url (format "~a~a"
                                   upload-to
                                   (path->string (file-name-from-path installer-file)))))
  (cond
    [(equal? (url-scheme url) "file")
     (copy-file installer-file
                (url->path url)
                #t)]
    [else
     (define i
       (put-pure-port
        url
        (file->bytes installer-file)
        (list (string-append "Description: " upload-desc))))
     (unless (equal? (read i) #t)
       (error "file upload failed"))]))

(display-time)
