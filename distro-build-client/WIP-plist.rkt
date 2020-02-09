#lang racket

(require xml/plist)

#|<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>com.apple.security.app-sandbox</key>
        <true/>
        <key>com.apple.security.cs.allow-jit</key>
        <true/>
        <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
        <true/>
        <key>com.apple.security.files.downloads.read-write</key>
        <true/>
        <key>com.apple.security.files.user-selected.read-write</key>
        <true/>
        <key>com.apple.security.network.client</key>
        <true/>
</dict>
</plist>
|#

(define entitlements
  '("com.apple.security.app-sandbox"
    "com.apple.security.cs.allow-jit"
    "com.apple.security.cs.allow-unsigned-executable-memory"
    "com.apple.security.files.downloads.read-write"
    "com.apple.security.files.user-selected.read-write"
    "com.apple.security.network.client"))

(define my-dict
  (cons
   'dict
   (for/list ([e (in-list entitlements)])
     (list 'assoc-pair e '(true)))))


(define-values (in out) (make-pipe))
(write-plist my-dict out)

(write-plist my-dict (current-output-port))
(close-output-port out)
(define new-dict (read-plist in))
(equal? my-dict new-dict)