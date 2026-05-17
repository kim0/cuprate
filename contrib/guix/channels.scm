(list
 (channel
  (name 'guix)
  (url "https://git.savannah.gnu.org/git/guix.git")
  (branch "master")
  ;; Commit pin should be updated intentionally during maintenance.
  ;; v1.5.0 (230aa373f3) only ships rust up to 1.88; cuprate's workspace
  ;; deps (fjall, lsm-tree, typed-index-collections, ...) need up to
  ;; rustc 1.91 today, so pin to a recent master that ships rust 1.93.
  (commit "7041be9c117cbae2a5238bb22a0ff93ef11ca91a")
  ;; Guix v1.5.0 requires every channel to carry an `introduction` with the
  ;; commit + OpenPGP fingerprint that started the chain of trust; without
  ;; this `guix time-machine` aborts with "channel 'guix' lacks an
  ;; introduction and cannot be authenticated". These values are the
  ;; canonical introduction for the official Guix channel.
  (introduction
   (make-channel-introduction
    "9edb3f66fd807b096b48283debdcddccfea34bad"
    (openpgp-fingerprint
     "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA")))))
