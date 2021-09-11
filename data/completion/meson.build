configure_file(
        input: 'bash_completion.in',
        output: 'pamac',
        configuration: conf,
        install: true,
        install_dir: join_paths(get_option('datadir'), 'bash-completion', 'completions'),
)
configure_file(
        input: 'zsh_completion.in',
        output: '_pamac',
        configuration: conf,
        install: true,
        install_dir: join_paths(get_option('datadir'), 'zsh', 'site-functions'),
)
configure_file(
        input: 'fish_completion.in',
        output: 'pamac.fish',
        configuration: conf,
        install: true,
        install_dir: join_paths(get_option('datadir'), 'fish', 'vendor_completions.d'),
)
