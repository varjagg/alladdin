(asdf:defsystem #:alladdin
  :description "Native Common Lisp client for local LLM backends via Ollama."
  :author "Eugene Zaikonnikov, Codex"
  :license "MIT"
  :depends-on (#:dexador
               #:babel
               #:yason)
  :serial t
  :components ((:file "src/package")
               (:file "src/core")))
