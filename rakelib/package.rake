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

  task :app_package_for_prod do
    pkg = JSON.parse File.read 'app/package.json'
    pkg['window']['toolbar'] = false
    pkg['window']['fullscreen'] = true
    pkg['window']['frame'] = true
    IO.write 'app/package.json', JSON.pretty_generate(pkg)
  end

  task :nw_build => [:copy_node_modules, :resolve_symlinks, :app_package_for_prod] do
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
    FileUtils.rm_rf 'build/'
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

    Dir['build/nw-json-explorer/*/*'].each do |app|
      puts ("Zipping release " + "#{app}.zip".yellow + "...")
      parent_dir = /[\w\/]+\/(?=[^$])/.match(app)[0]
      Zip::File.open "#{app}.zip", Zip::File::CREATE do |zip|
        Dir[app + "/**/*"].each {|f| zip.add((f.sub parent_dir, ""), f)}
      end
      puts ("Release " + "#{app}.zip".yellow + " OK".bold.green)
    end
  end

  task :pkg => [:resolve_symlinks, :copy_node_modules, :inject_userinfo, :copy_node_binary, :nw_build, :archive, :upload_to_s3]
end
