require 'highline'

class Epafh::App < Thor

	CONFIG_FILE = 'config/secrey.yml'

  include Thor::Actions
  default_task :crawl


  desc 'config', 'Initialize configuration'
  def config
    puts "Welcome to Epafh !".green
    cli = ::HighLine.new
    config = { 
      'imap' => {
        'server'   => '',
        'login'    => '',
        'password' => ''
      },
      'crm' => {
				'baseurl'  => '',
				'login'    => '',
				'password' => ''
      } 
    }
	  if File.exist? Epafh::EPAFI_CONFIG_FILE then
	    config.merge (YAML::load( File.open( Epafh::EPAFI_CONFIG_FILE ) ) || {})
	  end
    config['imap']['server'] = cli.ask("IMAP hostname ? ") do |q| 
      q.default = "imap.example.com" 
    end
    config['imap']['login'] = cli.ask("IMAP username ? ") do |q| 
      q.default = "john.smith@example.com" 
    end
    config['imap']['password'] = cli.ask("IMAP password ? ") do |q| 
      q.default = "blabla" ; q.echo = false 
    end
    FileUtils.mkdir_p (File.dirname(Epafh::EPAFI_CONFIG_FILE))
    File.open(Epafh::EPAFI_CONFIG_FILE, 'w'){|f| f.write(config.to_yaml)}
  end

  desc 'crawl', 'Crawls email to save mails'
  def crawl
    #saved_info = []
		parse_configuration

		## Run application
		app = Crawler.new @config

		app.connect!
		app.examine_all
		#pp saved_info
		app.disconnect!
  end

	def initialize *args
		@config = {}
		super
	end

	private


	def parse_configuration
		## Load configuration
		@config.merge! Hash.transform_keys_to_symbols(
			YAML::load( File.open( Epafh::EPAFI_CONFIG_FILE ) )
		)

		## Validate configuration structure 
		validations = {
			crm: {
				baseurl: lambda { |url| url =~ URI::regexp },
				login: 'string',
				password: 'string'
			},
			imap: {
				server: 'string',
				login: 'string',
				password: 'string'
			}
		}
		validator = HashValidator.validate(@config, validations)
		raise "Configuration is not valid: #{validator.errors.inspect}" unless validator.valid?
	end
end

