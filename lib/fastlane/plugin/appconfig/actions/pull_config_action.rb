require 'fastlane/action'
require 'fileutils'
require 'git'
require 'terminal-table'
require_relative '../helper/appconfig_helper'

module Fastlane
  module Actions

    class PullConfigAction < Action

      @@tmp_dir = "#{Dir.pwd}/.tmp"

      def self.run(params)
        remove_tmp_dir_if_exists

        bundle_id               = params[:bundle_id]
        bundled_files           = params[:bundled_files]
        bundled_encrypted_files = params[:bundled_encrypted_files]
        common_files            = params[:common_files]
        common_encrypted_files  = params[:common_encrypted_files]
        git_repo                = params[:git_repo]
        git_ref                 = params[:git_ref]
        passphrase              = params[:passphrase]
        project_path            = params[:project_path] || '.'

        title = 'Pull Config'
        headings = ['Parameter', 'Value']
        rows = []
        rows << ['bundle_id', bundle_id]
        rows << ['git_repo', git_repo]
        rows << ['git_ref', git_ref]
        rows << ['project_path', project_path]
        table = Terminal::Table.new :title => title, :headings => headings, :rows => rows
        puts("\n" + table.to_s + "\n")

        separator = "\n\t- "
        UI.message "bundled_files:#{separator}#{bundled_files.join(separator)}" unless bundled_files.empty?
        UI.message "bundled_encrypted_files:#{separator}#{bundled_encrypted_files.join(separator)}" unless bundled_encrypted_files.empty?
        UI.message "common_files:#{separator}#{common_files.join(separator)}" unless common_files.empty?
        UI.message "common_encrypted_files:#{separator}#{common_encrypted_files.join(separator)}" unless common_encrypted_files.empty?

        # Clone the repo
        git_name = git_repo.split('/').last
        git = Git.clone(git_repo, git_name, path: @@tmp_dir)
        git.checkout(git_ref)

        # Bundled files
        bundled_src = "#{@@tmp_dir}/#{git_name}/#{bundle_id}"
        copy_files(bundled_files, bundled_src, project_path)
        copy_and_decrypt_files(bundled_encrypted_files, bundled_src, project_path, passphrase)

        # Common files
        common_dst = "#{@@tmp_dir}/#{git_name}/common"
        copy_files(common_files, common_dst, project_path)
        copy_and_decrypt_files(common_encrypted_files, common_dst, project_path, passphrase)

        remove_tmp_dir_if_exists
      end

      def self.copy_files(files, source, project_path)
        files.each do |file|
          src = "#{source}/#{file}"
          dst = "#{Dir.pwd}/#{project_path}/#{file}"
          FileUtils.mkdir_p(File.dirname(dst))
          FileUtils.cp(src, dst)
        end
      end

      def self.copy_and_decrypt_files(files, source, project_path, passphrase)
        files.each do |file|
          src = "#{source}/#{file}"
          dst = "#{Dir.pwd}/#{project_path}/#{file}"
          decrypt(path: src, password: passphrase)
          FileUtils.cp(src, dst)
        end
      end

      def self.remove_tmp_dir_if_exists
        FileUtils.remove_dir(@@tmp_dir) if Dir.exist?(@@tmp_dir)
      end

      def self.description
        'This action will pull common and bundled files, and decrypt them if necessary, from a configuration repo'
      end

      def self.authors
        ['Ben Sarrazin']
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.details
        self.description
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :bundle_id,
            env_name: 'APPCONFIG_BUNDLE_ID',
            description: 'The bundle id of the configuration',
            optional: false,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :bundled_files,
            description: 'The list of file to store in a bundle',
            optional: true,
            default_value: [],
            type: Array
          ),
          FastlaneCore::ConfigItem.new(
            key: :bundled_encrypted_files,
            description: 'The list of encrypted files to store in a bundle',
            optional: true,
            default_value: [],
            type: Array
          ),
          FastlaneCore::ConfigItem.new(
            key: :common_files,
            description: 'The list of files to store in the common folder',
            optional: true,
            default_value: [],
            type: Array
          ),
          FastlaneCore::ConfigItem.new(
            key: :common_encrypted_files,
            description: 'The list of encrypted files to store in the common folder',
            optional: true,
            default_value: [],
            type: Array
          ),
          FastlaneCore::ConfigItem.new(
            key: :git_repo,
            env_name: 'APPCONFIG_GIT_REPO',
            description: 'The git repository where the configurations are stored',
            optional: false,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :git_ref,
            env_name: 'APPCONFIG_GIT_REF',
            description: 'The git reference (tag, branch or commit) of the configuration',
            optional: true,
            default_value: 'master',
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :passphrase,
            description: 'The passphrase used to encrypt the files',
            optional: false,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :project_path,
            default_value: '.',
            description: 'The path to the project directory relative to the root directory (useful for React Native style setups where the root directory is not the project directory)',
            optional: true,
            type: String
          )
        ]
      end

      def self.is_supported?(platform)
        true
      end

      # Stolen from Fastlane repo
      # The encryption parameters in this implementations reflect the old behaviour which depended on the users' local OpenSSL version
      # 1.0.x OpenSSL and earlier versions use MD5, 1.1.0c and newer uses SHA256, we try both before giving an error
      def self.decrypt(path: nil, password: nil, hash_algorithm: "MD5")
        stored_data = Base64.decode64(File.read(path))
        salt = stored_data[8..15]
        data_to_decrypt = stored_data[16..-1]

        decipher = OpenSSL::Cipher.new('AES-256-CBC')
        decipher.decrypt
        decipher.pkcs5_keyivgen(password, salt, 1, hash_algorithm)

        decrypted_data = decipher.update(data_to_decrypt) + decipher.final

        File.binwrite(path, decrypted_data)
        rescue => error
          fallback_hash_algorithm = "SHA256"
          if hash_algorithm != fallback_hash_algorithm
            decrypt(path, password, fallback_hash_algorithm)
        else
          UI.error(error.to_s)
          UI.crash!("Error decrypting '#{path}'")
        end
      end
    end
  end
end
