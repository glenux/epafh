module Epafh
  VERSION = "0.1.0"

	EPAFI_CONFIG_DIR = File.join(ENV['HOME'], '.epafh')
	EPAFI_CONFIG_FILE = File.join(EPAFI_CONFIG_DIR, 'config.yml')
	EPAFI_IGNORE_FILE = File.join(ENV['HOME'], '.epafh', 'ignore.yml')
end
