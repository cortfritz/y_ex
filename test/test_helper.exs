ExUnit.configure(capture_log: true)
ExUnit.start()

# Ensure we see all log levels during tests
Logger.configure(level: :debug)
