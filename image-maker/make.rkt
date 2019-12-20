#lang racket/base
(require racket/class
         racket/draw
         file/ico
         "pkg.rkt"
         "trash.rkt")

(define logo (read-bitmap "racket-logo.png"))

(define rising-W 683)
(define rising-H 385)

(define pkg-W 620)
(define pkg-H 418)

(define install-W 256)
(define install-H 256)

(define NSIS-scale 1)

(define header-W (* NSIS-scale 150))
(define header-H (* NSIS-scale 57))

(define welcome-W (* NSIS-scale 164))
(define welcome-H (* NSIS-scale 314))

(define bm (make-bitmap rising-W rising-H #:backing-scale 2))
(define pkg-bm (make-bitmap pkg-W pkg-H #:backing-scale 2))
(define install-bm (make-bitmap install-H install-W))
(define uninstall-bm (make-bitmap install-H install-W))
(define header-bm (make-bitmap header-W header-H #f))
(define welcome-bm (make-bitmap welcome-W welcome-H #f))

(define dc (send bm make-dc))
(define pkg-dc (send pkg-bm make-dc))
(define install-dc (send install-bm make-dc))
(define uninstall-dc (send uninstall-bm make-dc))
(define header-dc (send header-bm make-dc))
(define welcome-dc (send welcome-bm make-dc))

(send dc set-smoothing 'aligned)
(send pkg-dc set-smoothing 'aligned)
(send install-dc set-smoothing 'aligned)
(send uninstall-dc set-smoothing 'aligned)
(send header-dc set-smoothing 'smoothed)
(send welcome-dc set-smoothing 'smoothed)

(send dc set-pen (make-pen #:style 'transparent))
(send dc set-brush (make-brush #:color (make-color 255 255 255)))
(send dc draw-rectangle 0 0 rising-W rising-H)

(send pkg-dc set-pen (make-pen #:style 'transparent))
(send pkg-dc set-brush (make-brush #:color (make-color 255 255 255)))
(send pkg-dc draw-rectangle 0 0 pkg-W pkg-H)

(send dc set-scale 0.5 0.5)
(void (send dc draw-bitmap logo -80 -180))
(send dc set-scale 1 1)

(send pkg-dc set-scale 0.25 0.25)
(void (send pkg-dc draw-bitmap logo -500 80))
(send pkg-dc set-scale 1 1)

;(send dc set-brush (make-brush #:color (make-color 255 255 255 0.75)))
;(send dc draw-rectangle 0 0 rising-W rising-H)

(send dc set-brush (make-brush #:color "white"))
(send dc draw-rounded-rectangle
      (* rising-W 0.1)
      (* rising-H 0.25)
      (* rising-W 0.8)
      (* rising-H 0.5))

(send pkg-dc set-brush (make-brush #:color (make-color 255 255 255 0.5)))
(send pkg-dc draw-rectangle 0 0 pkg-W pkg-H)

(define (make-arrow-path i)
  (let ([p (new dc-path%)])
    (define j (quotient i 2))
    (send p move-to i (- 10 i))
    (send p line-to i (+ -10 i))
    (send p line-to (+ 30 i) (+ -10 i))
    (send p line-to (+ 30 i) (+ -25 (* 2 i) j))
    (send p line-to (- 55 i j) 0)
    (send p line-to (+ 30 i) (- 25 (* 2 i) j))
    (send p line-to (+ 30 i) (- 10 i))
    (send p close)
    (send p scale 2 2)
    p))

(define X 280)
(define Y 190)
    
(send dc set-brush (make-brush #:color "forestgreen"))
(send dc draw-path (make-arrow-path 2) X Y)

(send dc set-pen (make-pen #:color "white" #:width 2))
(send dc set-brush (make-brush #:style 'transparent))
(send dc draw-path (make-arrow-path 2) X Y)

(send install-dc scale 2.55 2.55)
(draw-pkg install-dc 0 0 logo)

(send uninstall-dc scale 2.55 2.55)
(draw-trash uninstall-dc 0 0 logo)

(send header-dc set-pen (make-pen #:style 'transparent))
(send header-dc draw-rectangle 0 0 header-W header-H)
(let* ([v-margin 10]
       [h-margin 6]
       [s (/ (- header-H (* 2 v-margin)) (send logo get-width))])
  (define t (send header-dc get-transformation))
  (send header-dc translate h-margin v-margin)
  (send header-dc scale s s)
  (send header-dc draw-bitmap logo 0 0)
  (send header-dc set-transformation t)
  (send header-dc set-font (make-font #:face "Cooper Hewitt"
                                      #:size (* NSIS-scale 32)))
  (define-values (w h d a) (send header-dc get-text-extent "Racket"))
  (send header-dc draw-text "Racket" (- header-W w h-margin) (/ (- header-H (- h d)) 2))
  (void))

(send welcome-dc set-pen (make-pen #:style 'transparent))
(send welcome-dc draw-rectangle 0 0 welcome-W welcome-H)
(let* ([margin 3]
       [s (/ (- welcome-W (* 2 margin)) (send logo get-width))])
  (define t (send welcome-dc get-transformation))
  (send welcome-dc translate margin margin)
  (send welcome-dc scale s s)
  (send welcome-dc draw-bitmap logo 0 0)
  (send welcome-dc set-transformation t)
  (void))

(void (send bm save-file "../distro-build-client/macosx-installer/racket-rising.png" 'png))
(void (send pkg-bm save-file "../distro-build-client/macosx-installer/pkg-bg.png" 'png))

(define (write-ico bm path)
  (define (resize bm s)
    (define small-bm (make-bitmap s s))
    (define dc (send small-bm make-dc))
    (send dc set-smoothing 'smoothed)
    (send dc scale (/ s 256) (/ s 256))
    (send dc draw-bitmap bm 0 0)
    small-bm)
  (define (bm->ico bm)
    (define s (send bm get-width))
    (define argb (make-bytes (* s s 4)))
    (send bm get-argb-pixels 0 0 s s argb)
    (argb->ico s s argb))
  (write-icos (list (bm->ico bm)
                    (bm->ico (resize bm 48))
                    (bm->ico (resize bm 32))
                    (bm->ico (resize bm 16)))
              path
              #:exists 'truncate))

(write-ico install-bm "../distro-build-client/windows-installer/installer.ico")
(write-ico uninstall-bm "../distro-build-client/windows-installer/uninstaller.ico")

(void (send header-bm save-file "../distro-build-client/windows-installer/header.bmp" 'bmp))
(void (send header-bm save-file "../distro-build-client/windows-installer/header-r.bmp" 'bmp))
(void (send welcome-bm save-file "../distro-build-client/windows-installer/welcome.bmp" 'bmp))
