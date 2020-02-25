# ob-playonline

`ob-playonline` enables online execution of org-babel src blocks.

This project is inspired by [ob-async](https://github.com/astahlman/ob-async).

## Installation

Install [playonline.el](https://github.com/twlz0ne/playonline.el) first, then clone this repository and add the following to your `.emacs`:

```elisp
(add-to-list 'load-path (expand-file-name "~/.emacs.d/site-lisp/ob-playonline"))
(require 'ob-playonline)
```

## Usage

Add `:playonline` to the header-args of org-babel src block, for example:

```
#+BEGIN_SRC python :results output :playonline
print('hello, python')
#+END_SRC
```
