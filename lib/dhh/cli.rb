# DHH::CLI: the one argv parser for the helpers and tools, with --help, usage errors and --file.

module DHH
  module CLI
    # The --file default as the tools' usage shows it.
    DEFAULT_DATASET = DHH::DATASET_PATH.delete_prefix("#{DHH::ROOT}/").freeze

    module_function

    # Flags are long-form only (--name); `values` and `switches` name them
    # without the dashes:
    #
    #   DHH::CLI.parse(argv, values: %w[type text], switches: %w[write], usage: USAGE)
    #   # => { 'type' => 'post', 'text' => 'Hello', 'write' => true }
    #
    # - `--help` anywhere prints `usage` and exits 0.
    # - A value flag takes the next element, unless that element is itself a known
    #   flag: `--text --write` is a missing value, never the text "--write".
    # - A missing value, an unknown flag or a stray argument aborts with the
    #   problem and the usage. A repeated flag keeps its last value.
    # - `positional: true` collects non-flag arguments under 'args' instead of
    #   rejecting them (helpers/fetch-avatars takes its handles that way).
    def parse(argv, values: [], switches: [], usage:, positional: false)
      if argv.include?('--help')
        puts usage
        exit 0
      end

      known = (values + switches).map { |name| "--#{name}" }
      options = {}
      options['args'] = [] if positional
      i = 0
      while i < argv.length
        arg = argv[i]
        name = arg.start_with?('--') ? arg[2..] : nil
        if name && values.include?(name)
          value = argv[i + 1]
          usage_error("missing value for #{arg}", usage) if value.nil? || known.include?(value)
          options[name] = value
          i += 1
        elsif name && switches.include?(name)
          options[name] = true
        elsif name
          usage_error("unknown flag: #{arg}", usage)
        elsif positional
          options['args'] << arg
        else
          usage_error("unexpected argument: #{arg}", usage)
        end
        i += 1
      end
      options
    end

    # Abort (exit 1) with the problem, a blank line and the usage.
    def usage_error(message, usage)
      abort("#{message}\n\n#{usage}")
    end

    # The dataset a tool reads or writes: --file, else data/entries.jsonl.
    # With must_exist, a missing file aborts.
    def dataset_path(options, must_exist:)
      path = options.fetch('file', DHH::DATASET_PATH)
      abort("#{path} does not exist") if must_exist && !File.exist?(path)
      path
    end
  end
end
