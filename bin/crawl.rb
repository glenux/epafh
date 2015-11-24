#!/usr/bin/env ruby

#require 'bundler/setup'
#Bundler.require

require 'pry'
require 'zlib'
require 'net/imap'
require 'pp'
require 'mechanize'
require 'yaml'
require 'hash_validator'
require 'uri'
require 'thor'
require 'json'
require 'mail'
require 'colorize'

#Net::IMAP.debug = true

class Hash
  #take keys of hash and transform those to a symbols
  def self.transform_keys_to_symbols(value)
    return value if not value.is_a?(Hash)
    hash = value.inject({}) do |memo,(k,v)| 
			memo[k.to_sym] = Hash.transform_keys_to_symbols(v); memo
		end
    return hash
  end
end

module Epafi
	EPAFI_CONFIG_FILE = File.join(ENV['HOME'],'.epafi','config.yml')
	EPAFI_IGNORE_FILE = File.join(ENV['HOME'],'.epafi','ignore.yml')

	class ContactManager

		CRM_LOGIN_URL = '/login'
		CRM_LEADS_URL = '/leads.json'
		CRM_CONTACTS_URL = '/contacts.json'


		def initialize config
			@config = config

			@browser = Mechanize.new { |agent|
				agent.user_agent_alias = 'Mac Safari'
			}
			@ignore_list = Set.new
			@keep_list = Set.new

			## Load configuration file
			#

			unless File.exist? EPAFI_CONFIG_FILE then
				raise "Unable to find configuration file #{EPAFI_CONFIG_FILE}" 
			end
			@config = config


			connect!
			load_contacts
			load_leads
			load_ignore
			#puts @keep_list.to_a
		rescue RuntimeError => e
			STDERR.puts e.message
		end

		def connect!
			@browser.get(@config[:crm][:baseurl] + CRM_LOGIN_URL) do |page|
				page.form_with(action: '/authentication') do |f|
					f['authentication[username]'] = @config[:crm][:login]
					f['authentication[password]'] = @config[:crm][:password]
				end.click_button
			end

		rescue Mechanize::ResponseCodeError
			raise "Authentication error. Verify your credentials." 
		end

		def load_ignore
			if File.exist? EPAFI_IGNORE_FILE
				ignore_list = YAML.load_file(EPAFI_IGNORE_FILE)
				ignore_list.each do |email|
					@ignore_list << email.strip.downcase
				end
			end
		end

		def load_leads page=1
			crm_leads_page = @browser.get(@config[:crm][:baseurl] + CRM_LEADS_URL + "?page=#{page}")
			crm_leads = JSON.parse crm_leads_page.body
			crm_leads.each do |lead_obj|
				keep_contact lead_obj['lead']['email'].split(',')
				keep_contact lead_obj['lead']['alt_email'].split(',')
			end

			if crm_leads.size > 0 then
				load_leads (page + 1)
			end
		end

		def load_contacts page=1
			crm_contacts_page = @browser.get(@config[:crm][:baseurl] + CRM_CONTACTS_URL + "?page=#{page}")
			crm_contacts = JSON.parse crm_contacts_page.body
			crm_contacts.each do |contact_obj|
				keep_contact contact_obj['contact']['email'].split(',')
	 			keep_contact contact_obj['contact']['alt_email'].split(',')
			end

			if crm_contacts.size > 0 then
				load_contacts (page + 1)
			end
			#contacts.to_a.sort.join(', ')
		end

		def keep_contact emails
			emails = emails.to_a if emails.is_a? Set
	 		[emails].flatten.each do |mail|
				@keep_list << mail.strip.downcase
			end
		end

		def ignore_contact emails
			emails = emails.to_a if emails.is_a? Set
	 		[emails].flatten.each do |mail|
				@ignore_list << mail.strip.downcase
			end
			File.open(EPAFI_IGNORE_FILE, 'w') do |f| 
				f.write @ignore_list.to_a.to_yaml 
			end
		end

		def include? mail
			return (
				(@ignore_list.include? mail.strip.downcase) or 
				(@keep_list.include? mail.strip.downcase)
			)
		end
	end

	class CrawlerApp
		attr_reader :imap
		attr_reader :contacts

		TMPMAIL_FILE = '.tmpmail'

		def initialize config
    	@saved_key = 'RFC822'
    	@filter_headers = 'BODY[HEADER.FIELDS (FROM TO Subject)]'.upcase
			@config = config
			@imap = nil
			@contact_manager = ContactManager.new config
		end


		def connect!
    	@imap = Net::IMAP.new(
				@config[:imap][:server], 
				ssl: {verify_mode: OpenSSL::SSL::VERIFY_NONE},
				port: 993
			)
    	@imap.login(@config[:imap][:login], @config[:imap][:password])
      #@imap.select(SOURCE_MAILBOX)
		end

		def disconnect!
    	imap.logout
    	imap.disconnect
		end

		MAIL_REGEXP = /\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b/

		def examine_message message
      m = Mail.read_from_string message.attr[@saved_key]
			return if m.from.nil?
			return if m.to.nil?


			emails = Set.new
      begin
			  emails.merge m.from
			  emails.merge [m.to].flatten if m.to
			  emails.merge [m.cc].flatten if m.cc
      rescue => e
        binding.pry
      end

			body_emails = Set.new
			m.body.parts.each do |part|
				next if part.content_type != 'text/plain'

				#body_emails = m.body.decoded.scan MAIL_REGEXP
				part_emails = part.decoded.scan MAIL_REGEXP
				#pp body_emails
				if not part_emails.empty? then
					body_emails.merge part_emails
				end
			end
			emails.merge body_emails

			# puts emails.to_a.join(' , ')
			remaining_emails = (
				emails
				.map{ |e| [e, (@contact_manager.include? e)] }
				.select{ |e,t| !t }
			)
			seen_emails = (
				remaining_emails
				.empty? 
			)
			# puts @contacts.to_a.join(', ')
			if seen_emails then
				print "."
				return
			else
				puts ""
				all_addr = { 
					from: (m.from || []),
					to: (m.to || []),
					cc: (m.cc || []),
					body: (body_emails || [])
				}
				all_addr.each do |key, list|
					list.each do |addr|
						addr_str = if remaining_emails.map{|e,t| e}.include? addr then
								   	     addr.yellow.on_black
							   	     else addr
							   	     end
						str = "%4s: %s" % [key.to_s.upcase, addr_str]
						puts str
					end
				end
				puts ""
				#puts " ORIGINAL EMAILS: #{emails.to_a.join(', ')}"
				#puts "REMAINING EMAILS: #{remaining_emails.map{|e,t| e}.join(', ')}".yellow.on_black
				#puts "     SEEN EMAILS: #{seen_emails}"
			end

			while true
				begin
					puts "\n### #{m.subject}"
					print "#{m.from.join(',')} --> #{m.to.join(',')} "
					puts "[Ignore/Add/Skip/Detail] ?"

					i = STDIN.gets 
					case i.strip
					when /^[iI]$/ then # ignore
						@contact_manager.ignore_contact remaining_emails.map{|e,t| e}
						break
					when /^[aA]$/ then # add
						@contact_manager.keep_contact remaining_emails.map{|e,t| e}
						break
					when /^[sS]$/ then #skip
						break
					when /^[dD]$/ then # decode
						# puts m.body.decoded
						File.open(TMPMAIL_FILE + ".2", 'w') do |f| 
							f.write message.attr[@saved_key]
						end
						system "formail < #{TMPMAIL_FILE}.2 > #{TMPMAIL_FILE}"
						system "mutt -R -f #{TMPMAIL_FILE}"
					end
				rescue Encoding::ConverterNotFoundError
					STDERR.puts "ERROR: encoding problem in email. Unable to convert."
				end
			end

			return
		end

		def examine_all
    	@imap.list('', '*').each do |mailbox|
				puts "\nMAILBOX #{mailbox.name}".yellow
				next unless mailbox.name =~ /#{@config[:imap][:pattern]}/
      	@imap.examine mailbox.name

        puts "Searching #{mailbox.name}"
      	messages_in_mailbox = @imap.responses['EXISTS'][0]
      	if not messages_in_mailbox then
        	say "#{mailbox.name} does not have any messages"
					next
				end

        @imap.select mailbox.name #GYR: TEST
        ids = @imap.search('SINCE 1-Jan-2001')
				# NOT OR TO "@agilefant.org" CC "@agilefant.org"')
        if ids.empty?
          puts "\tFound no messages"
				else
					examine_message_list mailbox.name, ids
				end
    	end
		end

		def examine_message_list mailbox_name, ids
      ids.each do |id|
        @imap.select mailbox_name #GYR: TEST
				message = imap.fetch(id, [@saved_key])[0]
				examine_message message
      end 
		rescue IOError
			# re-connect and try again
			connect!
			retry
		end
	end

	class Crawler < Thor

		CONFIG_FILE = 'config/secrey.yml'

  	include Thor::Actions
  	default_task :crawl


  	desc 'crawl', 'Crawls email to save mails'
  	def crawl
    	#saved_info = []
			parse_configuration

			## Run application
			app = CrawlerApp.new @config

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
				YAML::load( File.open( EPAFI_CONFIG_FILE ) )
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
end

Epafi::Crawler.start

