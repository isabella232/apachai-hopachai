# encoding: utf-8
require_relative '../apachai-hopachai'
require_relative 'command_utils'

module ApachaiHopachai
  class FinalizeCommand < Command
    include CommandUtils

    def self.description
      "Finalize test jobs"
    end

    def self.help
      puts new([]).send(:option_parser)
    end

    def self.require_libs
      require 'safe_yaml'
      require 'ansi2html/main'
      require 'mail'
      require 'erb'
      require 'base64'
      require 'stringio'
    end

    def self.default_options
      @@default_options ||= {
        :email_from => "Apachai Hopachai CI <#{`whoami`.strip}@localhost>",
        :email_subject => "[%{status}] %{repo_name} (%{before_commit} - %{commit})"
      }.freeze
    end

    def initialize(*args)
      super(*args)
      @options = self.class.default_options.dup
    end

    def start
      parse_argv
      read_and_verify_jobset
      generate_report
      send_notification
      save_report
    end

    private

    def option_parser
      require 'optparse'
      OptionParser.new do |opts|
        nl = "\n#{' ' * 37}"
        opts.banner = "Usage: appa finalize [OPTIONS] JOBSET_PATH"
        opts.separator "Run this on a jobset in which all jobs are completed. It will mark the entire jobset as complete."
        opts.separator ""
        
        opts.separator "Options:"
        opts.on("--report FILENAME", String, "Save report to this file instead of into the jobset") do |val|
          @options[:report] = val
        end
        opts.on("--format-report-filename", "Specify that the report filename is a format string.#{nl}" +
                "'%{status}' is substituted with the build status.") do
          @options[:format_report_filename] = true
        end
        opts.on("--email EMAIL", String, "Notify the given email address") do |val|
          @options[:email] = val
        end
        opts.on("--email-from EMAIL", String, "The From address for email notofications. Default: #{@options[:email_from]}") do |val|
          @options[:email_from] = val
        end
        opts.on("--email-subject STRING", String, "The subject for email notofications. Default: #{@options[:email_subject]}") do |val|
          @options[:email_subject] = val
        end
        opts.on("--log-level LEVEL", String, "Set log level. One of: fatal,error,warn,info,debug") do |val|
          set_log_level(val)
        end
        opts.on("--help", "-h", "Show help message") do
          @options[:help] = true
        end
      end
    end

    def parse_argv
      begin
        option_parser.parse!(@argv)
      rescue OptionParser::ParseError => e
        STDERR.puts e
        STDERR.puts
        STDERR.puts "Please see 'appa help finalize' for valid options."
        exit 1
      end

      if @options[:help]
        self.class.help
        exit 0
      end
      if @argv.size != 1
        self.class.help
        exit 1
      end

      @jobset_path = File.expand_path(@argv[0])
    end

    def read_and_verify_jobset
      abort "The given jobset does not exist" if !File.exist?(@jobset_path)
      abort "The given jobset is not complete" if !File.exist?("#{@jobset_path}/info.yml")
      @jobset_info = YAML.load_file("#{@jobset_path}/info.yml", :safe => true)
      if @jobset_info['file_version'] != '1.0'
        abort "job format version #{@jobset_info['file_version']} is unsupported"
      end
      
      @jobs = []
      Dir["#{@jobset_path}/*.appa-job"].each do |job_path|
        if job_processed?(job_path)
          @jobs << {
            :path   => job_path,
            :info   => YAML.load_file("#{job_path}/info.yml", :safe => true),
            :result => YAML.load_file("#{job_path}/result.yml", :safe => true)
          }
        else
          abort "job #{job_path} has not yet finished processing"
        end
      end
      @jobs.sort! { |a, b| a[:info]['id'] <=> b[:info]['id'] }
    end

    def job_processed?(job_path)
      File.exist?("#{job_path}/result.yml")
    end

    def generate_report
      @jobs.each do |job|
        log = File.open("#{job[:path]}/output.log", "rb") { |f| f.read }
        html_log = StringIO.new
        ANSI2HTML::Main.new(log, html_log)
        job[:html_log] = html_log.string.force_encoding('utf-8')
      end

      template = ERB.new(File.open("#{RESOURCES_DIR}/report.html.erb", "r") { |f| f.read })
      @report  = template.result(binding).force_encoding('binary')
    end

    def send_notification
      if @options[:email]
        @logger.info "Sending notification to #{@options[:email]}"
        info = symbolize_keys(@jobset_info).merge(:status => passed? ? 'Passed' : 'Failed')
        subject = @options[:email_subject] % info

        template = ERB.new(File.read("#{RESOURCES_DIR}/email.text.erb"))
        text_body = template.result(binding)

        mail = Mail.new
        mail[:from] = @options[:email_from]
        mail[:to]   = @options[:email]
        mail[:subject] = subject
        mail[:body] = text_body
        mail.add_file :filename => 'report-download-me-and-open-in-browser.html', :content => @report
        mail.delivery_method :sendmail
        mail.deliver
      end
    end

    def save_report
      @logger.info "Saving report to #{report_filename}"
      File.open(report_filename, "wb") do |f|
        f.write(@report)
      end
      File.open("#{@jobset_path}/finalized", "w").close
    end

    def report_filename
      @report_filename ||= begin
        if @options[:report]
          if @options[:format_report_filename]
            @options[:report] % { :status => passed? ? 'PASS' : 'FAIL' }
          else
            @options[:report]
          end
        else
          "#{@jobset_path}/report.html"
        end
      end
    end

    def symbolize_keys(hash)
      result = {}
      hash.each_pair do |key, val|
        result[key.to_sym] = val
      end
      result
    end

    ### Template helpers ###

    def h(text)
      ERB::Util.h(text)
    end

    def changeset_name
      @jobset_info['before_commit'] + " - " + @jobset_info['commit']
    end

    def passed?
      @jobs.all? { |job| job[:result]['passed'] }
    end

    def logo_data
      File.open("#{RESOURCES_DIR}/logo.png", "rb") { |f| f.read }
    end

    def start_time
      @jobs.map{ |j| j[:result]['start_time'] }.min
    end

    def finish_time
      @jobs.map{ |j| j[:result]['end_time'] }.max
    end

    def duration
      distance_of_time_in_hours_and_minutes(start_time, finish_time)
    end
  end
end
