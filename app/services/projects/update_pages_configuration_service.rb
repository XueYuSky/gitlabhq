# frozen_string_literal: true

module Projects
  class UpdatePagesConfigurationService < BaseService
    attr_reader :project

    def initialize(project)
      @project = project
    end

    def execute
      if update_file(pages_config_file, pages_config.to_json)
        reload_daemon
      end

      success
    rescue => e
      error(e.message)
    end

    private

    def pages_config
      {
        domains: pages_domains_config,
        https_only: project.pages_https_only?,
        id: project.project_id,
        access_control: !project.public_pages?
      }
    end

    def pages_domains_config
      enabled_pages_domains.map do |domain|
        {
          domain: domain.domain,
          certificate: domain.certificate,
          key: domain.key,
          https_only: project.pages_https_only? && domain.https?,
          id: project.project_id,
          access_control: !project.public_pages?
        }
      end
    end

    def enabled_pages_domains
      if Gitlab::CurrentSettings.pages_domain_verification_enabled?
        project.pages_domains.enabled
      else
        project.pages_domains
      end
    end

    def reload_daemon
      # GitLab Pages daemon constantly watches for modification time of `pages.path`
      # It reloads configuration when `pages.path` is modified
      update_file(pages_update_file, SecureRandom.hex(64))
    end

    def pages_path
      @pages_path ||= project.pages_path
    end

    def pages_config_file
      File.join(pages_path, 'config.json')
    end

    def pages_update_file
      File.join(::Settings.pages.path, '.update')
    end

    def update_file(file, data)
      unless data
        FileUtils.remove(file, force: true)
        return true
      end

      existing_data = read_file(file)
      if data == existing_data
        return false
      end

      temp_file = "#{file}.#{SecureRandom.hex(16)}"
      File.open(temp_file, 'w') do |f|
        f.write(data)
      end
      FileUtils.move(temp_file, file, force: true)

      true
    ensure
      # In case if the updating fails
      FileUtils.remove(temp_file, force: true)
    end

    def read_file(file)
      File.open(file, 'r') do |f|
        f.read
      end
    rescue
      nil
    end
  end
end
