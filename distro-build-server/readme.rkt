#lang at-exp racket/base
(require racket/format
         net/url
         (only-in "config.rkt" current-stamp))

(provide make-readme
         make-source-notes
         make-macosx-notes
         readme-system-type)

(define (maybe-stamp config)
  (if (hash-ref config '#:release? #f)
      ""
      @~a{ (@(current-stamp))}))

(define (make-readme config)
  @~a{
     The Racket Programming Language
     ===============================

     This is the
       @|(drop-sort-annotations (hash-ref config '#:name "Racket"))|
     distribution for version @(version)@(maybe-stamp config).@;

      @(if (let ([src? (hash-ref config '#:source? #f)])
             (or (hash-ref config '#:source-runtime? src?)
                 (hash-ref config '#:source-pkgs? src?)))
           (string-append "\n" (make-source-notes config) "\n")
           "")@;
      @(if (and (not (hash-ref config '#:source-runtime? 
                               (hash-ref config '#:source? #f)))
                (eq? (readme-system-type config) 'macosx))
           (string-append "\n" (make-macosx-notes config) "\n")
           "")@;
      @(let* ([catalogs (filter
                         (lambda (s) (not (equal? s "")))
                         (or (hash-ref config '#:dist-catalogs #f)
                             (let ([v (hash-ref config '#:dist-base-url #f)])
                               (and v
                                    (list (url->string
                                           (combine-url/relative (string->url v) "catalog/")))))
                             null))]
              [s (if (= 1 (length catalogs)) "" "s")]
              [is (if (= 1 (length catalogs)) "is" "are")])
         (if (null? catalogs)
             ""
             @~a{

                 The distribution has been configured so that when you install or
                 update packages, the package catalog@|s| at@;
                 @(apply ~a (for/list ([catalog (in-list catalogs)])
                              @~a{@"\n"  @|catalog|}))
                 @|is| consulted first.

                }))@;
      @(let* ([name (hash-ref config '#:install-name "")])
         (if (or (equal? name "")
                 (equal? name (version)))
             ""
             @~a{

                 The distribution has been configured so that the installation
                 name is
                   @name
                 Multiple installations with this name share `user'-scoped packages,
                 which makes it easier to upgrade from such an installation to this one.
                 To avoid sharing (which is better for keeping multiple installations
                 active) use `raco pkg config -i --set name ...' to choose a different
                 name for this installation.

                }))@;
     
     Visit http://racket-lang.org/ for more Racket resources.
     
     
     License
     -------
     
     Racket is distributed under the MIT license and the Apache version 2.0
     license, at your option.

     @(cond
        [(hash-ref config '#:source? #f)
         @~a{The Racket runtime system includes components distributed under
             other licenses. See "src/LICENSE.txt" for more information.}]
        [(eq? 'cs (hash-ref config '#:variant #f))
          @~a{The Racket runtime system embeds Chez Scheme, which is distributed
              under the Apache version 2.0 license.}]
        [else
          @~a{The Racket runtime system includes code distributed under the GNU
              Lesser General Public License, version 3.}])
     @(if (hash-ref config '#:source? #f)
          ""
          @~a{
     The runtime system remains separate as a shared library or
     additional executable, which means that it is dynamically linked
     and can be replaced with a modified variant by users, except
     for Windows executables that are created with the "embed DLLs"
     option.
     @(if (eq? 'cs (hash-ref config '#:variant #f))
          ""
          @~a{

              See the file "LICENSE-LGPL.txt" in "share" for the full text of the
              GNU Lesser General Public License.

              })
     See the file "LICENSE-APACHE.txt" in "share" for the full text of the
     Apache version 2.0 license.

     See the file "LICENSE-MIT.txt" in "share" for the full text of the
     MIT license.

     })
     Racket packages that are included in the distribution have their own
     licenses. See the package files in "pkgs" within "share" for more
     information.

     })

(define (drop-sort-annotations s)
  ;; Any number of spaces is allowed around "{...}" and "|",
  ;; so normalize that space while also removing "{...}":
  (regexp-replace* #rx" *[|] *"
                   (regexp-replace* #rx" *{[^}]*} *" s "")
                   " | "))

(define (make-source-notes config)
  (define src? (hash-ref config '#:source? #f))
  (define rt-src
    @~a{This distribution provides source for the Racket run-time system;
        for build and installation instructions, see "src/README.txt".})
  (define pkg-src
    @~a{(The distribution also includes the core Racket collections and any
        installed packages in source form.)})
  (define pkg-built
    @~a{Besides the run-time system's source, the distribution provides
        pre-built versions of the core Racket bytecode, as well as pre-built
        versions of included packages and documentation --- which makes it
        suitable for quick installation on a Unix platform for which
        executable binaries are not already provided.
        This option is recommended for ARM.})
  (cond
   [(and (hash-ref config '#:source-runtime? src?)
         (not (hash-ref config '#:source-pkgs? src?)))
    (~a rt-src "\n" pkg-built)]
   [(and (hash-ref config '#:source-runtime? src?)
         (hash-ref config '#:source-pkgs? src?))
    (~a rt-src "\n" pkg-src)]
   [else
    @~a{The distribution includes any pre-installed packages in source form.}]))

(define (make-macosx-notes config)
  (define vers-suffix
    (if (hash-ref config '#:versionless? #f)
        ""
        @~a{ v@(version)}))
  (if (hash-ref config '#:mac-pkg? #f)
      @~a{The installation directory is
            /Applications/@(string-append
                            (hash-ref config '#:dist-name "Racket")
                            (if (hash-ref config '#:release? #f)
                                ""
                                vers-suffix))
          The installer also adjusts "/etc/paths.d/racket" to point to that
          directory's "bin" directory, which adjusts the default PATH
          environment variable for all users.}
      @~a{Install by dragging the enclosing
            @|(hash-ref config '#:dist-name "Racket")|@|vers-suffix|
          folder to your Applications folder --- or wherever you like. You can
          move the folder at any time, but do not move applications or other
          files within the folder. If you want to use the Racket command-line
          programs, then (optionally) add the path of the "bin" subdirectory to
          your PATH environment variable.}))

(define (readme-system-type config)
  (or (hash-ref config '#:target-platform #f)
      (let ([c (hash-ref config '#:cross-target #f)])
        (or (and c
                 (cond
                  [(regexp-match? #rx"mingw" c)
                   'windows]
                  [(regexp-match? #rx"darwin" c)
                   'macosx]
                  [(regexp-match? #rx"linux" c)
                   'unix]
                  [else
                   #f]))
            (let ([p (hash-ref config '#:platform (system-type))])
              (if (or (eq? p 'windows/bash)
                      (eq? p 'windows/cmd))
                  'windows
                  p))))))
