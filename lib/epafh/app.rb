require 'highline'

class Epafh::App < Thor
  class InvalidConfiguration < RuntimeError ; end

	CONFIG_FILE = 'config/secrey.yml'
	CONFIG_DEFAULT = { 
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

  include Thor::Actions
  default_task :crawl


  desc 'config', 'Initialize configuration'
  def config
    puts "Welcome to Epafh !".green
    cli = ::HighLine.new
    config = CONFIG_DEFAULT
	  if File.exist? Epafh::EPAFI_CONFIG_FILE then
	    config =  config.merge(YAML::load( File.open( Epafh::EPAFI_CONFIG_FILE ) ) || {})
	  end
	  params = {
	    server: {desc: 'IMAP hostname ? ' },
	    login: {desc: 'IMAP username ? ' },
	    password: {desc: 'IMAP password ? ', hidden: true}
	  }
	  imap = config['imap']
	  # Ask parameters
    params.each.map {|param,values| [param.to_s,values] }
    .each do |param, values| 
      backup = imap[param]
      backup_hidden = imap[param].gsub(/./,'*')
      imap[param] = cli.ask(values[:desc]) do |q| 
        # Disable echo if hidden enabled
        q.echo = '*' if values[:hidden]

        # Replace default value by stars if hidden
        if not imap[param].empty? then
          q.default = 
            if (values[:hidden]) then backup_hidden
            else imap[param]
            end
        end
      end
      # When RETURN is pressed, Highline uses default (starred)
      # We have to replace it with the real value
      if values[:hidden] and imap[param] = backup_hidden then
        imap[param] = backup
      end
    end
    FileUtils.mkdir_p(Epafh::EPAFI_CONFIG_DIR)
    File.open(Epafh::EPAFI_CONFIG_FILE, 'w'){|f| f.write(config.to_yaml)}
  end

  desc 'crawl', 'Crawls email to save mails'
  def crawl
		parse_configuration

		## Run application
		app = Crawler.new @config

		app.connect!
		app.examine_all
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
		raise InvalidConfiguration, "Configuration is not valid: #{validator.errors.inspect}" unless validator.valid?
	end
end

