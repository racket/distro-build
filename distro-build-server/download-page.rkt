#lang at-exp racket/base
(require racket/format
         racket/path
         racket/system
         racket/list
         racket/date
         racket/file
         net/url
         (only-in file/sha1 bytes->hex-string)
         scribble/html
         (only-in plt-web site page call-with-registered-roots)
         (only-in plt-web/style columns))

(provide make-download-page
         get-installers-table
         (struct-out past-success))

(module+ main
  (require racket/cmdline)

  (define args null)
  (define (arg! kw val)
    (set! args (cons (cons kw val) args)))
  
  (define table-file
    (command-line
     #:once-each
     [("--at") url "URL for installers relative to download page"
      (arg! '#:installers-url url)]
     [("--dest") file "Write to <dest>"
      (arg! '#:dest file)]
     [("--git") dir "Report information from git clone <dir>"
      (arg! '#:git-clone dir)]
     [("--plt") "Use PLT web page style"
      (arg! '#:plt-web-style? #t)]
     #:args
     (table-file)
     table-file))

  (let ([args (sort args keyword<? #:key car)])
    (keyword-apply make-download-page
                   (map car args)
                   (map cdr args)
                   (list table-file))))

(define (get-installers-table table-file)
  (define table (call-with-input-file table-file read))
  (unless (hash? table) 
    (raise-user-error
     'make-download-page
     (~a "given file does not contain a hash table\n"
         "  file: ~a")
     table-file))
  table)

(struct past-success (name relative-url file version) #:prefab)

(define (make-download-page table-file
                            #:logs-table-file [logs-table-file #f]
                            #:past-successes [past-successes (hash)]
                            #:dest [dest "index.html"]
                            #:installers-url [installers-url "./"]
                            #:log-dir [log-dir #f]
                            #:log-dir-url [log-dir-url #f]
                            #:docs-url [docs-url #f]
                            #:pdf-docs-url [pdf-docs-url #f]
                            #:title [page-title "Racket Downloads"]
                            #:current-rx [current-rx #f]
                            #:version->current-rx [version->current-rx #f]
                            #:current-link-version [current-link-version (version)]
                            #:get-alias [get-alias (lambda (key inst) inst)]
                            #:git-clone [git-clone #f]
                            #:help-table [site-help (hash)]
                            #:help-fallbacks [site-help-fallbacks '()]
                            #:post-content [post-content null]
                            #:plt-www-site [www-site #f]
                            #:plt-web-style? [plt-style? (and www-site #t)])

  (define base-table (get-installers-table table-file))
  (define logs-table (if (and logs-table-file
                              (file-exists? logs-table-file))
                         (get-installers-table logs-table-file)
                         #hash()))

  (define table-data (for/fold ([table-data base-table]) ([(k v) (in-hash past-successes)])
                       (if (hash-ref table-data k #f)
                           table-data
                           (hash-set table-data k v))))

  (define (system*/string . args)
    (define s (open-output-string))
    (parameterize ([current-output-port s])
      (apply system* args))
    (get-output-string s))
  
  (define log-link
    (and log-dir-url
         (div (a class: "detail" href: log-dir-url "Build Logs"))))

  (define sorted
    (sort (hash-keys table-data) string<?
          #:key (lambda (s)
                  ;; treat `|` and `;` like a string terminator
                  (regexp-replace* #rx"[;|]" s "\0"))))
  (define sorted-and-split
    (map (lambda (s)
           (map (lambda (e)
                  (regexp-replace* #rx" *{[^}]*} *"
                                   e
                                   ""))
                (regexp-split #rx" *[|] *" s)))
         sorted))
  
  (define elems 
    (let loop ([l sorted-and-split]
               [keys sorted]
               [prev null]
               [started? #f])
      (define len (length prev))
      (define (add-sep l)
        (if (and started?
                 (null? prev))
            (cons '(#f) l)
            l))
      (cond
       [(null? l) `((#f) (#f ,nbsp))]
       [(or (<= (length (car l)) len)
            (not (equal? prev (take (car l) len))))
        ;; move out a layer:
        (loop l keys (drop-right prev 1) #t)]
       [(= (add1 len) (length (car l)))
        ;; a leaf entry:
        (add-sep
         (cons (cons (car keys)
                     (append (make-list len nbsp)
                             (list (list-ref (car l) len))))
               (loop (cdr l) (cdr keys) prev #t)))]
       [else
        ;; add a heder
        (define section (list-ref (car l) len))
        (add-sep
         (cons (cons #f
                     (append (make-list len nbsp) 
                             (list section)))
               (loop l keys (append prev (list section)) #t)))])))

  (define (xexpr->html p)
    (cond
      [(pair? p)
       (define op
         (case (car p)
           [(table) table]
           [(td) td]
           [(tr) tr]
           [(div) div]
           [else
            (lambda args (apply element (car p) args))]))
       (define has-attr? (or (and (pair? (cadr p))
                                  (pair? (caadr p)))
                             (null? (cadr p))))
       (apply op
              (append
               (if has-attr?
                   (let loop ([attrs (cadr p)])
                     (cond
                       [(null? attrs) null]
                       [else
                        (list* (string->symbol (format "~a:" (caar attrs)))
                               (cdar attrs)
                               (loop (cdr attrs)))]))
                   null)
               (map xexpr->html (if has-attr? (cddr p) (cdr p)))))]
      [(string? p) p]
      [(or (symbol? p) (number? p)) (entity p)]
      [else (error "unknown xexpr" p)]))

  (define (make-popup label content
                      #:overlay? [overlay? #f])
    (define id (~a "help" (gensym)))
    (define toggle (let ([elem (~a "document.getElementById" "('" id "')")])
                     (~a elem ".style.display = ((" elem ".style.display == 'inline') ? 'none' : 'inline');"
                         " return false;")))
    ((if overlay? reverse values)
     (list
      (div class: "helpbutton"
           (a href: "#"
              class: "helpbuttonlabel"
              onclick: toggle
              title: "explain"
              label))
      (div class: (if overlay? "hiddendrophelp" "hiddenhelp")
           id: id
           onclick: (if overlay? "" toggle)
           style: "display: none"
           (div class: (if overlay? "helpwidecontent" "helpcontent")
                (div class: "helptext"
                     (xexpr->html content)))))))

  (define (get-site-help last-col)
    (define h (or (hash-ref site-help last-col #f)
                  (and (string? last-col)
                       (for/or ([fb (in-list site-help-fallbacks)])
                         (and (regexp-match? (car fb) last-col)
                              (cadr fb))))))
    (if h
        (list* " " (make-popup (list nbsp "?" nbsp) h))
        null))
  
  (define (make-checksum path sha-bytes)
    `(span ([class "checksum"])
           ,(bytes->hex-string
             (call-with-input-file*
              path
              sha-bytes))))

  (define page-site (and plt-style?
                         (site "download-page"
                               #:url "http://page.racket-lang.org/"
                               #:navigation (if docs-url
                                                (list nbsp
                                                      nbsp
                                                      (a href: docs-url "Documentation")
                                                      (if pdf-docs-url
                                                          (a href: pdf-docs-url "PDF")
                                                          nbsp))
                                                null)
                               #:share-from (or www-site
                                                (site "www"
                                                      #:url "https://racket-lang.org/"
                                                      #:generate? #f)))))

  (define orig-directory (current-directory))

  (define checksum-in-popup? #f)

  (define page-headers
    (style/inline   @~a|{ 
                             .detail { font-size: small; font-weight: normal; }
                             .tinydetail { font-size: xx-small; font-weight: normal; }
                             .checksum, .path { font-family: monospace; }
                             .group { border-bottom : 2px solid #88c }
                             .major { font-weight : bold; font-size : large; left-border: 1ex; }
                             .minor { font-weight : bold; }
                             .download-table { border: 0px solid white; }
                             .download-table td { display: table-cell; padding: 0px 2px 0px 2px; border: 0px solid white; }
                             .helpbutton {
                                 display: inline;
                                 font-family: sans-serif;
                                 font-size : x-small;
                                 background-color: #ffffee;
                                 border: 1px solid black;
                                 border-radius: 1ex;
                                 vertical-align: top;
                             }
                             .helpbuttonlabel{ vertical-align: top; }
                             .hiddenhelp, .hiddendrophelp {
                                 width: 0em;
                                 position: absolute;
                                 z-index: 1;
                             }
                             .hiddendrophelp {
                                 top: 1em;
                             }
                             .helpcontent, .helpwidecontent {
                                 font-size : small;
                                 font-weight : normal;
                                 background-color: #ffffee;
                                 padding: 10px;
                                 border: 1px solid black;
                              }
                             .helpcontent {
                                 width: 20em;
                             }
                             .helpwidecontent {
                                 width: 42em;
                             }
                            a { text-decoration: none; }
                           }|))

  (define (strip-detail s)
    (if (string? s)
        (regexp-replace #rx";.*" s "")
        s))

  (define (add-detail s e)
    (define m (and (string? s)
                   (regexp-match #rx"(?<=; )(.*)$" s)))
    (cond
     [m
      (span e (span class: "detail"
                    nbsp
                    (cadr m)))]
     [else e]))

  (define page-body
    (list
     (if page-title
         ((if plt-style? h3 h2) page-title)
         null)
     (table
      class: "download-table"
      (for/list ([elem (in-list elems)])
        (define key (car elem))
        (define inst (and key (hash-ref table-data key)))
        (define mid-cols (if (null? (cdr elem))
                             #f
                             (drop-right (cdr elem) 1)))
        (define last-col (last elem))
        (define level-class
          (case (length elem)
            [(2) "major"]
            [(3) "minor"]
            [else "subminor"]))
        (define row-level-class
          (if key
              "nongroup"
              (case (length elem)
                [(2) "group"]
                [(3) "subgroup"]
                [else "subsubgroup"])))
        (define num-cols (if (or current-rx
                                 version->current-rx)
                             "7"
                             "5"))
        (cond
         [(not mid-cols)
          (tr (td colspan: num-cols nbsp))]
         [inst
          (tr (td
               (for/list ([col (in-list mid-cols)])
                 (span nbsp nbsp nbsp))
               (add-detail
                last-col
                (if (past-success? inst)
                    ;; Show missing installer
                    (span class: (string-append "no-installer " level-class)
                          (strip-detail last-col))
                    ;; Link to installer
                    (a class: (string-append "installer " level-class)
                       href: (url->string
                              (combine-url/relative
                               (string->url installers-url)
                               inst))
                       (strip-detail last-col))))
               (get-site-help last-col))
              (td nbsp)
              (td (if (past-success? inst)
                      (span class: "detail" "")
                      (span class: "detail"
                            (~r (/ (file-size (build-path (path-only table-file)
                                                          inst))
                                   (* 1024 1024))
                                #:precision 1)
                            " MB")))
              (td nbsp)
              (td (if (past-success? inst)
                      (span class: "detail"
                            (if (and log-dir 
                                     (file-exists? (build-path log-dir (hash-ref logs-table key key))))
                                (list
                                 (a href: (url->string
                                           (combine-url/relative
                                            (string->url log-dir-url)
                                            (hash-ref logs-table key key)))
                                    "build failed")
                                 "; ")
                                null)
                            "last success: "
                            (a href: (~a (past-success-relative-url inst))
                               (past-success-name inst)))
                      (let ([path (build-path (path-only table-file)
                                              inst)])
                        (if checksum-in-popup?
                            (span class: "detail"
                                  style: "position: relative"
                                  (make-popup
                                   #:overlay? #t
                                   (list nbsp nbsp "click for SHA1 and SHA256" nbsp nbsp)
                                   `(span
                                     (div "SHA1:" nbsp
                                          ,(make-checksum path sha1-bytes))
                                     (div "SHA256:" nbsp
                                          ,(make-checksum path sha256-bytes)))))
                            (span class: "tinydetail"
                                  "SHA256:" nbsp (xexpr->html (make-checksum path sha256-bytes)))))))
              (let ([current-rx (or current-rx
                                    (and version->current-rx
                                         (version->current-rx
                                          (if (past-success? inst)
                                              (past-success-version inst)
                                              current-link-version))))])
                (if current-rx
                    (list
                     (td nbsp)
                     (td (span class: "detail"
                               (let* ([inst-path (get-alias
                                                  key
                                                  (if (past-success? inst)
                                                      (past-success-file inst)
                                                      inst))])
                                 (if (regexp-match? current-rx inst-path)
                                     (a href: (url->string
                                               (combine-url/relative
                                                (string->url installers-url)
                                                (bytes->string/utf-8
                                                 (regexp-replace current-rx
                                                                 (string->bytes/utf-8 inst-path)
                                                                 #"current"))))
                                        "as " ldquo "current" rdquo)
                                     nbsp)))))
                    null)))]
         [else
          (tr class: row-level-class
              (td class: level-class
                  colspan: num-cols
                  (for/list ([col (in-list mid-cols)])
                    (span nbsp nbsp nbsp))
                  (add-detail
                   last-col
                   (strip-detail last-col))
                  (get-site-help last-col)))])))
     (if (and docs-url
              (not site))
         (p (a href: docs-url "Documentation")
            (if pdf-docs-url
                (list
                 nbsp
                 nbsp
                 (span class: "detail"
                       (a href: pdf-docs-url "[also available as PDF]")))
                null))
         null)
     (if git-clone
         (let ([git (find-executable-path "git")])
           (define origin (let ([s (system*/string git "remote" "show" "origin")])
                            (define m (regexp-match #rx"(?m:Fetch URL: (.*)$)" s))
                            (if m
                                (cadr m)
                                "???")))
           (define stamp (system*/string git "log" "-1" "--format=%H"))
           (p
            (div (span class: "detail" "Repository: " (span class: "path" origin)))
            (div (span class: "detail" "Commit: " (span class: "checksum" stamp)))
            (or log-link null)))
         null)
     (if (and log-link (not git-clone))
         (p log-link)
         null)
     post-content))

  (define-values (dest-dir dest-file dest-is-dir?) (split-path dest))

  (define page-content
    (if page-site
        (page #:site page-site
              #:file (path-element->string dest-file)
              #:title page-title
              #:extra-headers page-headers
              (columns 12 #:row? #t
                       page-body))
        (html (head (title page-title)
                    page-headers)
              (body page-body))))

  (call-with-registered-roots
   (lambda ()
     (cond
      [page-site
       ;; Render to "download-page", then move up:
       (define base-dir (if (path? dest-dir)
                            dest-dir
                            (current-directory)))
       (parameterize ([current-directory base-dir])
         (render-all))
       (define dp-dir (build-path base-dir "download-page"))
       (for ([f (in-list (directory-list dp-dir))])
         (define f-dest (build-path base-dir f))
         (delete-directory/files f-dest #:must-exist? #f)
         (rename-file-or-directory (build-path dp-dir f) f-dest))
       (delete-directory dp-dir)]
      [else
       (call-with-output-file* 
        dest
        #:exists 'truncate/replace
        (lambda (o)
          (output-xml page-content o)))]))))
