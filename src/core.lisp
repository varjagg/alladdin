(in-package #:alladdin)

(defparameter +json-omit+ (gensym "JSON-OMIT"))

(defclass llm-backend ()
  ((default-model
    :initarg :default-model
    :initform nil
    :accessor backend-default-model)
   (default-embed-model
    :initarg :default-embed-model
    :initform nil
    :accessor backend-default-embed-model)
   (connect-timeout
    :initarg :connect-timeout
    :initform 10
    :accessor backend-connect-timeout)
   (request-timeout
    :initarg :request-timeout
    :initform 600
    :accessor backend-request-timeout)))

(defclass ollama-backend (llm-backend)
  ((base-url
    :initarg :base-url
    :initform "http://localhost:11434/api"
    :accessor backend-base-url)
   (keep-alive
    :initarg :keep-alive
    :initform "5m"
    :accessor backend-keep-alive)
   (default-chat-options
    :initarg :default-chat-options
    :initform nil
    :accessor backend-default-chat-options)))

(defun make-ollama-backend (&key
                              (base-url "http://localhost:11434/api")
                              default-model
                              default-embed-model
                              (connect-timeout 10)
                              (keep-alive "5m")
                              (request-timeout 600)
                              default-chat-options)
  (make-instance 'ollama-backend
                 :base-url base-url
                 :default-model default-model
                 :default-embed-model default-embed-model
                 :connect-timeout connect-timeout
                 :keep-alive keep-alive
                 :request-timeout request-timeout
                 :default-chat-options default-chat-options))

(defun trim-slashes (string)
  (string-trim "/" string))

(defun backend-url (backend path)
  (format nil "~A/~A"
          (string-right-trim "/" (backend-base-url backend))
          (trim-slashes path)))

(defun json-key-name (key)
  (typecase key
    (string key)
    (symbol
     (substitute #\_ #\-
                 (string-downcase (symbol-name key))))
    (t
     (princ-to-string key))))

(defun json-object (&rest pairs)
  (let ((object (make-hash-table :test #'equal)))
    (loop for (key value) on pairs by #'cddr
          unless (eq value +json-omit+)
            do (setf (gethash (json-key-name key) object) value))
    object))

(defun json-boolean (value)
  (if value
      yason:true
      yason:false))

(defun json-encode-to-string (object)
  (with-output-to-string (stream)
    (yason:encode object stream)))

(defun response-body-string (body)
  (typecase body
    (string body)
    ((vector (unsigned-byte 8))
     (babel:octets-to-string body :encoding :utf-8))
    (t
     (princ-to-string body))))

(defun parse-json-string (string)
  (let ((yason:*parse-object-as* :hash-table)
        (yason:*parse-json-arrays-as-vectors* t))
    (yason:parse string)))

(defun parse-json-response (body)
  (let ((text (string-trim '(#\Space #\Tab #\Newline #\Return)
                           (response-body-string body))))
    (or (ignore-errors (parse-json-string text))
        (let* ((lines (remove ""
                              (uiop:split-string text :separator '(#\Newline))
                              :test #'string=))
               (chunks (map 'vector #'parse-json-string lines)))
          (if (= (length chunks) 1)
              (aref chunks 0)
              chunks)))))

(defun merge-option-tables (base override)
  (cond
    ((null base) override)
    ((null override) base)
    (t
     (let ((merged (make-hash-table :test (hash-table-test base))))
       (maphash (lambda (key value)
                  (setf (gethash key merged) value))
                base)
       (maphash (lambda (key value)
                  (setf (gethash key merged) value))
                override)
       merged))))

(defun ensure-json-object (value)
  (typecase value
    (hash-table value)
    (list (apply #'json-object value))
    (t value)))

(defun sequence->vector (value)
  (typecase value
    (vector value)
    (list (coerce value 'vector))
    (t value)))

(defun resolve-model-or-die (candidate fallback operation)
  (or candidate
      fallback
      (error "No model configured for ~A." operation)))

(defun make-chat-message (role content &key images)
  (let ((message (json-object "role" role
                              "content" content)))
    (when images
      (setf (gethash "images" message) (sequence->vector images)))
    message))

(defgeneric backend-request (backend method path &key payload))

(defmethod backend-request ((backend ollama-backend) method path &key payload)
  (let* ((url (backend-url backend path))
         (body (and payload (json-encode-to-string payload)))
         (headers '(("Accept" . "application/json")
                    ("Content-Type" . "application/json")))
         (response (dexador:request url
                                    :method method
                                    :headers headers
                                    :content body
                                    :connect-timeout
                                    (backend-connect-timeout backend)
                                    :read-timeout
                                    (backend-request-timeout backend))))
    (parse-json-response response)))

(defgeneric health-check (backend))

(defmethod health-check ((backend ollama-backend))
  (backend-request backend :get "version"))

(defgeneric list-models (backend))

(defmethod list-models ((backend ollama-backend))
  (let ((response (backend-request backend :get "tags")))
    (or (gethash "models" response)
        #())))

(defun available-model-names (backend)
  (let ((models (list-models backend)))
    (loop for model across models
          collect (gethash "name" model))))

(defgeneric chat (backend messages
                  &key model response-format stream options tools keep-alive))

(defmethod chat ((backend ollama-backend) (messages list)
                 &key model response-format (stream nil) options tools keep-alive)
  (let* ((effective-model
           (resolve-model-or-die model
                                 (backend-default-model backend)
                                 'chat))
         (effective-options
           (merge-option-tables (backend-default-chat-options backend)
                                (and options (ensure-json-object options))))
         (payload
           (json-object
            "model" effective-model
            "messages" (sequence->vector messages)
            "stream" (json-boolean stream)
            "format" (or response-format +json-omit+)
            "options" (or effective-options +json-omit+)
            "tools" (or (and tools (sequence->vector tools))
                        +json-omit+)
            "keep_alive" (or keep-alive
                             (backend-keep-alive backend)
                             +json-omit+))))
    (backend-request backend :post "chat" :payload payload)))

(defmethod chat ((backend ollama-backend) (messages vector)
                 &rest initargs
                 &key model response-format (stream nil) options tools keep-alive
                 &allow-other-keys)
  (declare (ignore model response-format stream options tools keep-alive))
  (apply #'chat backend (coerce messages 'list) initargs))

(defmethod chat ((backend ollama-backend) (messages string)
                 &rest initargs
                 &key model response-format (stream nil) options tools keep-alive
                 &allow-other-keys)
  (declare (ignore model response-format stream options tools keep-alive))
  (apply #'chat backend (list (make-chat-message "user" messages)) initargs))

(defun chat-response-message (response)
  (typecase response
    (hash-table (gethash "message" response))
    (vector
     (and (> (length response) 0)
          (chat-response-message (aref response (1- (length response))))))
    (t nil)))

(defun chat-response-content (response)
  (typecase response
    (hash-table
     (let ((message (chat-response-message response)))
       (and message
            (gethash "content" message))))
    (vector
     (with-output-to-string (stream)
       (loop for chunk across response
             for content = (chat-response-content chunk)
             when content
               do (write-string content stream))))
    (t nil)))

(defun chat-response-tool-calls (response)
  (typecase response
    (hash-table
     (let ((message (chat-response-message response)))
       (and message
            (gethash "tool_calls" message))))
    (vector
     (loop for chunk across response
           for tool-calls = (chat-response-tool-calls chunk)
           when tool-calls
             do (return tool-calls)))
    (t nil)))

(defgeneric embed-texts (backend texts
                         &key model truncate keep-alive dimensions))

(defmethod embed-texts ((backend ollama-backend) (texts list)
                        &key model (truncate +json-omit+) keep-alive dimensions)
  (let* ((effective-model
           (resolve-model-or-die model
                                 (or (backend-default-embed-model backend)
                                     (backend-default-model backend))
                                 'embed-texts))
         (payload
           (json-object
            "model" effective-model
            "input" (sequence->vector texts)
            "truncate" (if (eq truncate +json-omit+)
                           +json-omit+
                           (json-boolean truncate))
            "keep_alive" (or keep-alive
                             (backend-keep-alive backend)
                             +json-omit+)
            "dimensions" (or dimensions +json-omit+))))
    (backend-request backend :post "embed" :payload payload)))

(defmethod embed-texts ((backend ollama-backend) (texts vector)
                        &rest initargs
                        &key model truncate keep-alive dimensions
                        &allow-other-keys)
  (declare (ignore model truncate keep-alive dimensions))
  (apply #'embed-texts backend (coerce texts 'list) initargs))

(defmethod embed-texts ((backend ollama-backend) (text string)
                        &rest initargs
                        &key model truncate keep-alive dimensions
                        &allow-other-keys)
  (declare (ignore model truncate keep-alive dimensions))
  (apply #'embed-texts backend (list text) initargs))

(defun embed-response-vectors (response)
  (or (gethash "embeddings" response)
      #()))
