#lang at-exp racket/base
(require racket/system
         racket/file
         racket/format
         racket/runtime-path
         racket/port
         ds-store
         ds-store/alias
         ds-store/cross-alias
         compiler/exe-dylib-path
         setup/cross-system
         xml/plist
         "notarize.rkt")

(provide installer-dmg
         make-dmg)

;; important documentation on the signing process appears in Apple's Tech Note 2206,
;; online at https://developer.apple.com/library/archive/technotes/tn2206/_index.html

;; save this here? check entitlements with codesign -d --entitlements :- /path/to/myapp.app

(define hdiutil "/usr/bin/hdiutil")
(define osascript "/usr/bin/osascript")
(define codesign "/usr/bin/codesign")

(define (find-exe name)
  (or (find-executable-path name)
      (error 'find-exe "cannot find ~s" name)))

;; Use cross tools when these are available:
(define hfsplus (find-executable-path "hfsplus"))     ; also needs `mkfs.hfsplus` and `dmg`

;; NB it's very possible that the hardened runtime & entitlements
;; are required only on the top-level binaries....
(define (run-codesign sign-identity sign-cert f hardened-runtime?
                      #:skip-remove? [skip-remove? #f])
  (unless (or skip-remove? sign-cert)
    ;; remove any existing signature before trying to add a new one:
    (system*/show codesign "--remove-signature" f
                  #:ignore-failure? #t))
  (define (sign-cert-path key)
    (define path (hash-ref sign-cert key))
    (define dir (hash-ref sign-cert 'p12-dir #f))
    (if dir
        (build-path dir path)
        path))
  (cond
    [hardened-runtime?
     (define entitlements-file (write-entitlements-file!))
     (cond
       [sign-cert
        (system*/show (find-exe "rcodesign")
                      "sign"
                      "--for-notarization"
                      "--code-signature-flags" "hard"
                      "--entitlements-xml-file" (path->string entitlements-file)
                      "--p12-file" (sign-cert-path 'p12-file)
                      "--p12-password-file" (sign-cert-path 'p12-password-file)
                      f)]
       [else
        (system*/show codesign "-s" sign-identity
                      "-o" "runtime" ; use the hardened runtime
                      "--timestamp"  ; apply a trusted timestamp
                      "--entitlements" (path->string entitlements-file)
                      f)])
     (delete-file entitlements-file)]
    [else
     (cond
       [sign-cert
        (system*/show (find-exe "rcodesign")
                      "sign"
                      "--p12-file" (sign-cert-path 'p12-file)
                      "--p12-password-file" (sign-cert-path 'p12-password-file)
                      f)]
       [else
        (system*/show codesign "-s" sign-identity f)])]))

(define-runtime-path bg-image "macosx-installer/racket-rising.png")

(define (system*/show #:ignore-failure? [ignore-failure? #f]
                      #:quiet? [quiet? #f]
                      . l)
  (displayln (apply ~a #:separator " " l))
  (flush-output)
  (unless (if quiet?
              (parameterize ([current-output-port (open-output-nowhere)])
                (apply system* l))
              (apply system* l))
    (unless ignore-failure?
      (error "failed"))))

(define (make-dmg volname src-dir dmg bg readme sign-identity sign-cert
                  #:hardened-runtime? [hardened-runtime? #t])
  (define tmp-dmg (make-temporary-file "~a.dmg"))
  (define tmp2-dmg (make-temporary-file "~a.dmg"))
  (define work-dir
    (let-values ([(base name dir?) (split-path src-dir)])
      (build-path base "work")))
  (when (file-exists? dmg) (delete-file dmg))
  (delete-directory/files work-dir #:must-exist? #f)
  (make-directory* work-dir)
  (printf/flush "Copying ~a\n" src-dir)
  (define dest-dir (build-path work-dir volname))
  (copy-directory/files src-dir dest-dir
                        #:preserve-links? #t
                        #:keep-modify-seconds? #t)
  (when readme
    (call-with-output-file*
     (build-path work-dir volname "README.txt")
     #:exists 'truncate
     (lambda (o)
       (display readme o))))
  (when bg
    (copy-file bg (build-path work-dir ".bg.png")))
  (unless (and (string=? sign-identity "") (not sign-cert))
    (sign-executables dest-dir sign-identity sign-cert hardened-runtime?))
  (cond
    [(not hfsplus)
     ;; Use Mac-specific tools...
     ;; The following command should work fine, but it looks like hdiutil in 10.4
     ;; is miscalculating the needed size, making it too big in our case (and too
     ;; small with >8GB images).  It seems that it works to first generate an
     ;; uncompressed image and then convert it to a compressed one.
     ;;   hdiutil create -format UDZO -imagekey zlib-level=9 -ov \
     ;;           -mode 555 -volname volname -srcfolder . dmg
     ;; So, first create an uncompressed image...
     (parameterize ([current-directory work-dir])
        (system*/show hdiutil
                      "create" "-format" "UDRW" "-fs" "HFS+" "-ov"
                      "-mode" "755" "-volname" volname "-srcfolder" "."
                      tmp-dmg))
     ;; Then do the expected dmg layout...
     (when bg
       (dmg-layout tmp-dmg volname ".bg.png"))
     ;; the call to convert is failing with
     ;; `resource temporarily unavailable.hdiutil: convert: result: 35`.
     ;; internet search suggests that the problem is that the dmg is still listed as being opened by
     ;; diskimage-helper or some other process, and copying the file appears to solve the problem.
     ;; there may be a solution that doesn't use so much space...
     (displayln (~v (list 'copy-file tmp-dmg tmp2-dmg #t)))
     (copy-file tmp-dmg tmp2-dmg #t)
     ;; And create the compressed image from the uncompressed image:
     (system*/show hdiutil
                   "convert" "-format" "UDBZ" "-imagekey" "zlib-level=9" "-ov"
                   tmp2-dmg "-o" dmg)]
    [else
     ;; Use cross tools...
     ;; We're expecting the HFS+ creation tools to be deterministic enough
     ;; that the `#:file-inode` and `#:parent-inode` are always these values:
     (define file-inode 16)
     (define root-inode 2)
     (define bg-alias (path->synthesized-alias-bytes #:volume-name volname
                                                     #:file-name ".bg.png"
                                                     #:file-inode file-inode
                                                     #:parent-name volname
                                                     #:parent-inode root-inode
                                                     #:file-absolute-name (string-append volname ":.bg.png")
                                                     #:file-absolute-path-within-volume "/.bg.png"
                                                     #:volume-maybe-absolute-path (string-append "/Volumes/" volname)))
     (write-layout work-dir bg-alias volname)
     (define mb (estimate-megabytes work-dir))
     (parameterize ([current-directory work-dir])       
       (define symlinks (for/hash ([from (in-directory)]
                                   #:when (link-exists? from))
                          (define to (resolve-path from))
                          (delete-file from) ; avoid confusing `addall`
                          (values (path->string from)
                                  (if (path? to)
                                      (path->string to)
                                      to))))
       (system*/show (find-exe "dd") "if=/dev/zero"
                     (format "of=~a" tmp-dmg)
                     "bs=1M" (format "count=~a" mb))
       (system*/show (find-exe "mkfs.hfsplus")
                     "-v" volname
                     tmp-dmg)
       (system*/show #:quiet? #t
                     hfsplus
                     tmp-dmg
                     "addall"
                     ".")
       (for ([(from to) (in-hash symlinks)])
         (make-file-or-directory-link to from) ; restore link
         (system*/show hfsplus
                       tmp-dmg
                       "symlink"
                       from
                       to)))
     (system*/show (find-exe "dmg")
                   "dmg"
                   tmp-dmg
                   dmg)])
  (delete-file tmp-dmg)
  (delete-file tmp2-dmg))

(define (framework-dir? f)
  (regexp-match? #rx#"\\.framework$" f))

(define (sign-executables dest-dir sign-identity sign-cert hardened-runtime?)
  ;; sign the mach-o files in any frameworks in the given directory
  (define (check-frameworks dir)
    (for ([f (in-list (directory-list dir #:build? #t))])
      (when (and (directory-exists? f)
                 (framework-dir? f))
        (cond
          [(and sign-cert
                (file-exists? (build-path f "Resources/Info.plist")))
           ;; need to sign the bundle as a whole when using `rcodesign`
           (printf/flush "Signing bundle ~v\n" f)
           (run-codesign sign-identity sign-cert f hardened-runtime?)]
          [else
           (printf/flush "Signing content ~v\n" f)
           ;; some frameworks have a Versions directory, some don't.
           ;; must sign every version... specifically, each twice-subdir of the Versions
           ;; directory.
           (define versions-dir (build-path f "Versions"))
           (cond [(directory-exists? versions-dir)
                  (for ([version-name (in-list (directory-list versions-dir #:build? #t))])
                    (sign-mach-o-files-in-dir sign-identity sign-cert hardened-runtime? version-name))]
                 [else
                  (sign-mach-o-files-in-dir sign-identity sign-cert hardened-runtime? f)])]))))
  (define (check-apps dir)
    (for ([f (in-list (directory-list dir #:build? #t))])
      (when (and (directory-exists? f)
                 (regexp-match #rx#".app$" f))
        (define name (let-values ([(base name dir?) (split-path f)])
                       (path-replace-suffix name #"")))
        (define exe (build-path f "Contents" "MacOS" name))
        (when (file-exists? exe)
          ;; Move a copy of the `Racket` framework into the ".app", if needed:
          (define lib-path (find-matching-library-path exe "Racket"))
          (define rx #rx"^@executable_path/[.][.]/[.][.]/[.][.]/lib/Racket.framework/")
          (when (and lib-path (regexp-match? rx lib-path))
            ;; Get shared library's path after "Racket.framework":
            (define orig-so (substring lib-path (cdar (regexp-match-positions rx lib-path))))
            ;; Copy the shared library:
            (define so (build-path (build-path f "Contents" "MacOS" "Racket")))
            (copy-file (build-path (build-path f 'up "lib" "Racket.framework" orig-so))
                       so)
            ;; If there's a "boot" directory, make a link, because the shared
            ;; library expects to find it adjacent:
            (define orig-boot-dir (let-values ([(base name dir?) (split-path orig-so)])
                                    (build-path 'up "lib" "Racket.framework" base "boot")))
            (when (directory-exists? (build-path f orig-boot-dir))
              (make-file-or-directory-link (build-path 'up 'up orig-boot-dir)
                                           (build-path f "Contents" "MacOS" "boot")))
            ;; Sign library:
            (run-codesign sign-identity sign-cert so hardened-runtime?)
            ;; Update executable to point to the adjacent copy of "Racket"
            (update-matching-library-path exe "Racket" "@executable_path/Racket"))
          ;; Sign ".app":
          (run-codesign sign-identity sign-cert f hardened-runtime?)))))
  (sign-mach-o-files-in-dir sign-identity sign-cert hardened-runtime? (build-path dest-dir "bin"))
  (sign-mach-o-files-in-dir sign-identity sign-cert hardened-runtime? (build-path dest-dir "lib"))
  (check-apps dest-dir)
  (check-apps (build-path dest-dir "lib"))
  (check-frameworks (build-path dest-dir "lib")))

(define (printf/flush . args)
  (apply printf args)
  (flush-output))

;; sign all of the mach-o files in a directory
(define (sign-mach-o-files-in-dir sign-identity sign-cert hardened-runtime? dir)
  (cond [(directory-exists? dir)
         (for ([f (in-list (directory-list dir #:build? #t))])
           (when (mach-o-file? f)
             (run-codesign sign-identity sign-cert f hardened-runtime?)))]
        [else
         (printf "WARNING: directory passed to sign-mach-o-files-in dir doesn't exist: ~e"
                 dir)
         (flush-output)]))

;; is this a Mach-O file? (That is, does it start with #xfeedface or #xfeedfacf ?
(define (mach-o-file? file)
  (cond
    [(file-exists? file)
     (define-values (exe-id file-type)
       (call-with-input-file file
                             (lambda (i)
                               (define bstr (read-bytes 4 i))
                               (void (read-bytes 8 i))
                               (define type-bstr (read-bytes 4 i))
                               (if (and (bytes? bstr)
                                        (bytes? type-bstr)
                                        (= 4 (bytes-length bstr))
                                        (= 4 (bytes-length type-bstr)))
                                    (values (integer-bytes->integer bstr #f)
                                            (integer-bytes->integer type-bstr #f))
                                    (values #f #f)))))       
     (and (member exe-id '(#xFeedFace #xFeedFacf))
          ;; executables or shared library:
          (member file-type '(2 6)))]
    [else #f]))

(define (dmg-layout dmg volname bg)
  (define-values (mnt del?)
    (let ([preferred (build-path "/Volumes/" volname)])
      (if (not (directory-exists? preferred))
          ;; Use the preferred path so that the alias is as
          ;; clean as possible:
          (values preferred #f)
          ;; fall back to using a temporary directory
          (values (make-temporary-file "~a-mnt" 'directory) #t))))
  (system*/show hdiutil
                "attach" "-readwrite" "-noverify" "-noautoopen"
                "-mountpoint" mnt dmg)
  (define alias (path->alias-bytes (build-path mnt bg)
                                   #:wrt mnt))
  (write-layout mnt alias volname)
  ;; Neither `hdiutil detach` nor using Finder to detach the disk works on all
  ;; systems. So try one, then the other.
  (with-handlers ([exn:fail? (lambda _ (system*/show hdiutil "detach" mnt))])
    (system*/show osascript
                  "-e" "tell application \"Finder\""
                  "-e" (~a "eject \"" volname "\"")
                  "-e" "end tell"))
  (when del?
    (delete-directory mnt)))

(define (write-layout mnt bg-alias volname)
  (make-file-or-directory-link "/Applications" (build-path mnt "Applications"))
  (define (->path s) (string->path s))
  (write-ds-store (build-path mnt ".DS_Store")
                  (list
                   (ds 'same 'BKGD 'blob 
                       (bytes-append #"PctB"
                                     (integer->integer-bytes (bytes-length bg-alias) 4 #t #t)
                                     (make-bytes 4 0)))
                   (ds 'same 'ICVO 'bool #t)
                   (ds 'same 'fwi0 'blob 
                       ;; Window location (size overridden below), sideview off:
                       (fwind 160 320 540 1000 'icnv #f))
                   (ds 'same 'fwsw 'long 135) ; window sideview width?
                   (ds 'same 'fwsh 'long 380) ; window sideview height?
                   (ds 'same 'icgo 'blob #"\0\0\0\0\0\0\0\4") ; ???
                   (ds 'same 'icvo 'blob
                       ;; folder view options:
                       #"icv4\0\200nonebotm\0\0\0\0\0\0\0\0\0\4\0\0")
                   (ds 'same 'icvt 'shor 16) ; icon label size
                   (ds 'same 'pict 'blob bg-alias)
                   (ds (->path ".bg.png") 'Iloc 'blob (iloc 900 180)) ; file is hidden, anyway
                   (ds (->path "Applications") 'Iloc 'blob (iloc 500 180))
                   (ds (->path volname) 'Iloc 'blob (iloc 170 180)))))

;; this wrapper function computes the dmg name, makes the dmg, signs it, and
;; returns the path to it.
(define (installer-dmg human-name base-name dist-suffix readme
                       sign-identity sign-cert notarization-config
                       #:hardened-runtime? [hardened-runtime? #t])
  (define dmg-name (format "bundle/~a-~a~a.dmg"
                           base-name
                           (cross-system-library-subpath #f)
                           dist-suffix))
  (make-dmg human-name "bundle/racket" dmg-name bg-image readme sign-identity sign-cert
            #:hardened-runtime? hardened-runtime?)
  ;; sign whole DMG too, for Sierra
  (unless (and (string=? sign-identity "") (not sign-cert))
    (run-codesign sign-identity sign-cert dmg-name hardened-runtime? #:skip-remove? #t))
  (when notarization-config
    (notarize-file/config dmg-name notarization-config))
  dmg-name)

(define entitlements
  '("com.apple.security.cs.allow-jit"
    "com.apple.security.cs.allow-unsigned-executable-memory"
    ;; these are used by Bogdan Popa, but it looks to me like if we
    ;; don't opt into the app-sandbox, we don't need the remainder of
    ;; the entitlements
    #;("com.apple.security.app-sandbox"
    "com.apple.security.files.downloads.read-write"
    "com.apple.security.files.user-selected.read-write"
    "com.apple.security.network.client")))

;; represent the entitlements as a plist dictionary
(define entitlements-dict
  (cons
   'dict
   (for/list ([e (in-list entitlements)])
     (list 'assoc-pair e '(true)))))


;; hmm, let's try the raw text from Bogdan Popa:
;; ... okay, adding dyld-environment-variables and disable-library-validation

(define entitlements-text
#<<|
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>com.apple.security.cs.allow-jit</key>
        <true/>
        <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
        <true/>
        <key>com.apple.security.inherit</key>
        <true/>
        <key>com.apple.security.cs.allow-dyld-environment-variables</key>
        <true/>
        <key>com.apple.security.cs.disable-library-validation</key>
        <true/>
</dict>
</plist>
|
)

;; generate an entitlements file, in a temporary file
(define (write-entitlements-file!)
  (define filename (make-temporary-file "entitlements-~a"))
  (call-with-output-file filename
    #:exists 'truncate
    (λ (port)
      (display entitlements-text port)
      #;(write-plist entitlements-dict port)))
  filename)

(define (estimate-megabytes d)
  (define (estimate-bytes d)
    (define node-size 4096)
    (for/fold ([n 0]) ([f (in-directory d)])
      (+ n       
         node-size
         (cond
           [(link-exists? f) 0]
           [(file-exists? f) (file-size f)]
           [else 0]))))
  (define m (* 1024 1024))
  (define s (estimate-bytes d))
  (quotient (+ s (quotient s 2) m) m))
