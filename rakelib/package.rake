require 'highline/import'
require 'fileutils'
require 'colored'
require 'json'
require 'rfc822'
require 'git'
require 'zip'


namespace :build do

  task :resolve_symlinks do
    files = Dir["./app/*"].keep_if {|f| File.symlink? f}.map {|f| [f, File.readlink(f)]}

    files.each do |symlink, resolved|
      File.delete symlink
      FileUtils.cp_r "app/#{resolved}", symlink
    end
  end

  task :copy_node_modules do
    CONFIG['node_vendor'].each do |dep|
      dir_dep = "./node_modules/#{dep}"
      unless Dir.exist? dir_dep
        LOGGER.error "Node dependency: directory not found: #{dir_dep}"
        next
      end
      FileUtils.rm_rf "./app/node_modules/#{dep}"
      FileUtils.cp_r dir_dep, "./app/node_modules/"
    end
  end

  def parse_git_status(line)
    status = nil
    i = 0
    while status.nil? and i < 3
      case line[i]
      when '?' then status = 'untracked'; break
      when 'A' then status = 'added'; break
      when 'M' then status = 'modfied'; break
      else i += 1
      end
    end
    [status, line.slice(3, line.size)]
  end

  task :validate_clean_git do
    res = `git status --porcelain`
    uncommited = []
    res.each_line do |line|
      status, filepath = parse_git_status line

      important = %w{app src config node_modules bower.json package.json}
      if important.any? {|i| filepath.start_with? i}
        uncommited << [status, filepath]
      end
    end

    if uncommited.size > 1
      puts "#{"Error: uncommited files.".bold.red} Here is the list: "
      puts uncommited.map {|s, f| "#{s.yellow}: #{f.green}"}.join ""
      puts "Please commit your files before packaging the application".bold.yellow
      return false
    end
  end

  task :inject_userinfo do

    g = Git.open '.'
    last_commit = g.log.first
    infos = {
      created_at: 1409583994,
      app_id: "zwr38eon",
      release: {
        last_authored: last_commit.author.name,
        last_message: last_commit.message,
        commit: last_commit.to_s
      }
    }
    if ENVIRONMENT.dev?
      infos[:name] = "John Steplogger"
      infos[:email] = "intercom@feetme.epimeros.org"
    elsif ENVIRONMENT.test?
      infos[:name] = "Circle Ci"
      infos[:email] = "mackwic+fm_circle_logs@gmail.com"
    elsif ENVIRONMENT.prod?
      infos[:name] = ENV['FM_NAME'] if ENV['FM_NAME']
      if infos[:name].nil?
        puts "Please provide user #{"Firstname".bold.cyan} and #{"Lastname".bold.cyan} separated by a space (Default: #{"Enki Unknown Bilal".yellow})"
        infos[:name] = ask("First Last? ") do |q|
          q.readline = true
          q.validate = /\w+ \w+/
          q.default = 'Enki Unknown Bilal'
        end
      end
      infos[:email] = ENV['FM_EMAIL'] if ENV['FM_EMAIL']
      if infos[:email].nil?
        puts "Please provide the user #{"email".bold.cyan} (Default: intercom+unknown_profile@feetme.epimeros.org)"
        infos[:email] = ask("Email? ") do |q|
          q.readline = true
          q.validate = RFC822::EMAIL_REGEXP_WHOLE
          q.default = "intercom+unknown_profile@feetme.epimeros.org"
        end
      end
    else
      raise "Unknown environment ! FATAL ERROR.".bold.red
    end
    # last checks becasue we don't know...
    if infos[:name].nil?
      raise ("Invalid user name: ".red + (infos[:name] || "null").yellow )
    end
    if infos[:email].nil? or (RFC822::EMAIL_REGEXP_WHOLE.match infos[:email]).nil?
      raise "Invalid user email: ".red + (infos[:email] || "null").yellow
    end
    IO.write "app/userinfo.json", infos.to_json
  end

  task :app_package_for_prod do
    pkg = JSON.parse File.read 'app/package.json'
    pkg['window']['toolbar'] = false
    pkg['window']['fullscreen'] = true
    pkg['window']['frame'] = true
    IO.write 'app/package.json', JSON.pretty_generate(pkg)
  end

  task :nw_build => [:inject_userinfo, :copy_node_modules, :resolve_symlinks, :app_package_for_prod] do
    # re-generate the index.html in production mode
    sh "ENVIRONMENT=prod bundle exec rake build:html"

    # comma separated values of the platform we want to build to, defaults to current, osx otherwise
    platforms = (ENVIRONMENT['FM_BUILD_PLATFORMS']) || 'osx'
    unless (ENVIRONMENT['FM_BUILD_PLATFORMS'])
      if (OS == 'Darwin')
        platforms = 'osx'
      elsif (OS == 'Linux')
        platforms = if ARCH == 'x86_64' then 'linux64' else 'linux32' end
      elsif (OS == 'Win')
        platforms = 'win'
      end
    end
    opts = [
      "--platforms #{platforms}",
      "--version 0.8.6",
      "--buildDir build/"
    ].join " "
    # Provide an empty local db and reboot the build dir
    FileUtils::mkdir_p 'app/db'
    FileUtils.rm_rf 'build/feetme'
    if (OS != 'Win')
      # we need "ulimit -n 8096" b/c we open too many files
      sh "ulimit -n 8096 && ./node_modules/node-webkit-builder/bin/nwbuild #{opts} app"
    end
    # restore the app/package.json file
    `git checkout app/package.json`
  end

  task :copy_node_binary do
    if OS == 'Darwin'
      Dir["app/workers"].each do |app|
        sh "cp /usr/local/bin/node #{app}/node" unless File.exist? "#{app}/node"
      end
    elsif OS == 'Linux'
      ENVIRONMENT['PATH'].each_line(':') {|s|
        if /\/.nvm\//.match(s) != nil
          Dir["app/workers"].each do |app|
            sh "cp #{s.chop}/node #{app}/node"
          end
        end
      }
    else
      raise "FIXME: unsupported OS !"
    end
  end

  task :archive do
    Zip.setup do |z|
      z.continue_on_exists_proc = true # overide existing zips
      # z.unicode_names = true # needed for accents on windows < 7
      z.default_compression = Zlib::BEST_COMPRESSION
    end

    Dir['build/feetme/*/feetme*'].each do |app|
      puts ("Zipping release " + "#{app}.zip".yellow + "...")
      parent_dir = /[\w\/]+\/(?=[^$])/.match(app)[0]
      Zip::File.open "#{app}.zip", Zip::File::CREATE do |zip|
        Dir[app + "/**/*"].each {|f| zip.add((f.sub parent_dir, ""), f)}
      end
      puts ("Release " + "#{app}.zip".yellow + " OK".bold.green)
    end
  end

  task :upload_to_s3 => :validate_clean_git do
    require 'aws-sdk-v1'
    s3 = AWS::S3.new({
      region: 'eu-west-1',
      access_key_id: "AKIAIJT2SVIPS3L5G43A",
      secret_access_key: "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",
    })

    Dir['build/feetme/*'].each do |os|
      app = Dir["#{os}/feetme*.zip"].first
      userinfo = JSON.parse(File.read("app/userinfo.json"))
      username = userinfo['name'].downcase.gsub! ' ', '-'
      release = userinfo['release']
      commit = release['commit']
      commit_url = "https://github.com/mackwic/steplogger/commit/#{commit}"
      commit = commit[commit.size - 8, commit.size - 1]
      release_name = "feetme-#{username}-#{commit}.zip"

      puts "Uploading #{release_name.yellow} to S3...".green
      release_obj = s3.buckets['fm-releases'].objects[release_name]
      release_obj.write(Pathname.new(app), {
        reduced_redundancy: true,
        metadata: release
        #single_request: true
      })
      release_obj.acl = :public_read
      puts "upload to S3: OK !".bold.green

      slack_message = {
        mrkdwn: true,
        channel: '#software',
        username: 'A wild release appears !',
        icon_emoji: ':shipit:',
        text: "Wow. Such release. Much features. WOW !\n<#{release_obj.public_url(secure: true)}|Download #{release_name}>",
        attachments: [
          {
            color: 'good',
            fields: [
              {
                title: 'Release Author',
                value: `git config user.name`,
                short: true
              },
              {
                title: 'Commit Author',
                value: release['last_authored'],
                short: true
              },
              {
                title: 'Commit Message',
                value: release['last_message'],
                short: true,
                mrkdwn_in: ['value']
              },
              {
                title: 'Commit',
                value: "<#{commit_url}|#{commit}>",
                short: true,
                mrkdwn_in: ["value"]
              }
            ]
          }
        ]
      }
     cmd = "curl -X POST --data-urlencode 'payload=#{slack_message.to_json}' https://feet-me.slack.com/services/hooks/incoming-webhook?token=EMAO2EZHW6ezpWdkr0hxnZVF"
     sh cmd
    end

  end

  task :pkg => [:resolve_symlinks, :copy_node_modules, :inject_userinfo, :copy_node_binary, :nw_build, :archive, :upload_to_s3]
end
