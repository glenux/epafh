class Epafh::ContactManager

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
