(list
 (channel
  (name 'guix)
  (url "https://git.savannah.gnu.org/git/guix.git")
  (branch "master")
  ;; Commit pin should be updated intentionally during maintenance.
  ;; Pinned to the v1.5.0 tag commit.
  (commit "230aa373f315f247852ee07dff34146e9b480aec")
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
