# encoding: UTF-8

# DB Updater
class DbUpdater
  FILES = %w(
    local_vulnerable_files.xml local_vulnerable_files.xsd malwares.txt
    plugins_full.txt plugins.txt themes_full.txt themes.txt
    timthumbs.txt user-agents.txt wp_versions.xml wp_versions.xsd
    plugin_vulns.json theme_vulns.json wp_vulns.json
  )

  attr_reader :repo_directory

  def initialize(repo_directory)
    @repo_directory = repo_directory

    fail "#{repo_directory} is not writable" unless \
      Pathname.new(repo_directory).writable?
  end

  # @return [ Hash ] The params for Typhoeus::Request
  def request_params
    {
      ssl_verifyhost: 2,
      ssl_verifypeer: true
    }
  end

  # @return [ String ] The raw file URL associated with the given filename
  def remote_file_url(filename)
    "https://raw.githubusercontent.com/wpscanteam/vulndb/master/#{filename}"
  end

  # @return [ String ] The checksum of the associated remote filename
  def remote_file_checksum(filename)
    url = "#{remote_file_url(filename)}.sha512"

    res = Browser.get(url, request_params)
    fail "Unable to get #{url}" unless res.code == 200
    res.body
  end

  def local_file_path(filename)
    File.join(repo_directory, "#{filename}")
  end

  def local_file_checksum(filename)
    Digest::SHA512.file(local_file_path(filename)).hexdigest
  end

  def backup_file_path(filename)
    File.join(repo_directory, "#{filename}.back")
  end

  def create_backup(filename)
    return unless File.exist?(local_file_path(filename))
    FileUtils.cp(local_file_path(filename), backup_file_path(filename))
  end

  def restore_backup(filename)
    return unless File.exist?(backup_file_path(filename))
    FileUtils.cp(backup_file_path(filename), local_file_path(filename))
  end

  def delete_backup(filename)
    FileUtils.rm(backup_file_path(filename))
  end

  # @return [ String ] The checksum of the downloaded file
  def download(filename)
    file_path = local_file_path(filename)
    file_url  = remote_file_url(filename)

    res = Browser.get(file_url, request_params)
    fail "Error while downloading #{file_url}" unless res.code == 200
    File.open(file_path, 'wb') { |f| f.write(res.body) }

    local_file_checksum(filename)
  end

  def update(verbose = false)
    FILES.each do |filename|
      begin
        puts "[+] Checking #{filename}" if verbose
        db_checksum = remote_file_checksum(filename)

        # Checking if the file needs to be updated
        if File.exist?(local_file_path(filename)) && db_checksum == local_file_checksum(filename)
          puts '  [i] Already Up-To-Date' if verbose
          next
        end

        puts '  [i] Needs to be updated' if verbose
        create_backup(filename)
        puts '  [i] Backup Created' if verbose
        puts '  [i] Downloading new file' if verbose
        dl_checksum = download(filename)
        puts "  [i] Downloaded File Checksum: #{dl_checksum}" if verbose

        unless dl_checksum == db_checksum
          fail "#{filename}: checksums do not match"
        end
      rescue => e
        puts '  [i] Restoring Backup due to error' if verbose
        restore_backup(filename)
        raise e
      ensure
        if File.exist?(backup_file_path(filename))
          puts '  [i] Deleting Backup' if verbose
          delete_backup(filename)
        end
      end
    end
  end
end
