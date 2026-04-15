(defpackage #:alladdin
  (:use #:cl)
  (:export
   #:llm-backend
   #:ollama-backend
   #:backend-base-url
   #:backend-default-model
   #:backend-default-embed-model
   #:backend-connect-timeout
   #:backend-keep-alive
   #:backend-request-timeout
   #:backend-default-chat-options
   #:make-ollama-backend
   #:make-chat-message
   #:health-check
   #:list-models
   #:available-model-names
   #:chat
   #:chat-response-message
   #:chat-response-content
   #:chat-response-tool-calls
   #:embed-texts
   #:embed-response-vectors))

(in-package #:alladdin)
