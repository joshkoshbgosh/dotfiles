-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Emacs: keep a daemon running, then open a GUI frame that connects to it.
-- Both wrappers live in ~/.local/bin (stowed from the dotfiles repo).
o.exec_on_start("emacs-daemon")
o.launch_on_start("emacs-client")
