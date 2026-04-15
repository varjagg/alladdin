# Alladdin

`Alladdin` is a small Common Lisp client for local LLM backends. Right
now it implements Ollama's native HTTP API.

## Minimal Use

```lisp
(asdf:load-system :alladdin)

(let* ((backend (alladdin:make-ollama-backend
                 :default-model "qwen3:8b"
                 :request-timeout 900))
       (reply (alladdin:chat backend
                             "Reply with exactly the word ready.")))
  (alladdin:chat-response-content reply))
```

## Explicit Messages

```lisp
(let* ((backend (alladdin:make-ollama-backend
                 :default-model "qwen3:8b"))
       (messages (list (alladdin:make-chat-message
                        "system"
                        "You answer tersely.")
                       (alladdin:make-chat-message
                        "user"
                        "List three fruits.")))
       (reply (alladdin:chat backend messages)))
  (alladdin:chat-response-content reply))
```

## Notes

- The default backend URL is `http://localhost:11434/api`.
- The default read timeout is `600` seconds to tolerate slow local model
  startup.
- `chat` handles both ordinary JSON responses and newline-delimited
  streamed JSON chunks returned by Ollama.

## License

MIT
