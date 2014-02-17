# encoding: utf-8
module ApachaiHopachai
  VERSION_STRING       = '1.0.0'
  APP_ROOT             = File.expand_path(File.dirname(__FILE__) + "/..")
  DATABASE_CONFIG_FILE = "#{APP_ROOT}/config/database.yml"
  MODELS_DIR           = "#{APP_ROOT}/models"
  RESOURCES_DIR        = "#{APP_ROOT}/resources"
  SANDBOX_IMAGE_NAME   = "phusion/apachai-hopachai-sandbox"
  SUPERVISOR_COMMAND   = "/usr/local/rvm/bin/rvm-exec ruby-2.1.0 ruby /appa/bin/supervisor"
  SANDBOX_JOB_RUNNER_COMMAND = "/sbin/setuser appa /usr/local/rvm/bin/rvm-exec 2.1.0 ruby /appa/bin/job_runner"

  def self.config
    # TODO: introduce config file
    { 'storage_path' => File.expand_path("#{APP_ROOT}/../tmp") }
  end

  def self.default_logger
    @@logger ||= begin
      logger = Logger.new(STDOUT)
      logger.level = Logger::INFO
      logger
    end
  end
end
