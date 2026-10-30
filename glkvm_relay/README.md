# GLKVM Relay

GL.iNet's self-hosted GLKVM Cloud relay (`rttys`) and a TURN server (coturn) on the Home Assistant host: one web console for the GL.iNet KVMs on your network, with no separate server. It starts with nothing typed: credentials are generated on the first start and shown on the Configuration tab, TURN learns each KVM's address when it registers, and the TURN credential is replaced by raising one option. See `DOCS.md`.
