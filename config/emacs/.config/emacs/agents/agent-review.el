;; -*- lexical-binding: t -*-
;;; agents/agent-review.el — Agent review

(use-package agent-review
  :straight (agent-review
              :type git
              :host github
              :repo "nineluj/agent-review")
  :commands agent-review)


