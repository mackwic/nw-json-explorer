require 'fileutils'

class ::Hash
  def deep_merge(second)
    merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : v2 }
    self.merge(second, &merger)
  end

  def deep_merge!(second)
    merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge!(v2, &merger) : v2 }
    self.merge!(second, &merger)
  end

  def require(required_keys)
    # substract the two set
    missing_keys = required_keys - self.keys
    unless missing_keys.size == 0
      raise "The keys #{missing_keys} are required in the Hash!"
    end
    self
  end
end

class FMConfig < Hash

  def initialize(conf)
    base_path = "#{conf[:dir]}/#{conf[:name]}"
    [
      ("%s.yaml" % base_path),
      ("%s.%s.yaml" % [base_path, OS]),
      ("%s.%s.yaml" % [base_path, ENVIRONMENT]),
      ("%s.%s.%s.yaml" % [base_path, ENVIRONMENT, OS])
    ].each {|file| deep_merge_if_exist file}
  end

  def parse_public_config
    return nil if self['config'].nil?
    res = {}
    self['config'].each_pair do |key, value|
      res[key] = value
    end
    res
  end

  def to_slim
    """
  javascript:
    window.CONFIG = #{public_config};
    Object.freeze(window.CONFIG);
"""
  end

  private

  def deep_merge_if_exist(file)
    self.deep_merge! load_if_exist file
  end

  def load_if_exist(path)
    if File.exists? path
      LOGGER.debug "loading #{path}"
      YAML.load(File.read path)
    else
      LOGGER.debug "file #{path} doesn't exist. Don't load anything"
      return {}
    end
  end

  def public_config
    parse_public_config.to_json
  end
end

class ::Object
  def present?
    not self.nil?
  end

  def try(*a, &b)
    if a.empty? && block_given?
      yield self
    else
      public_send(*a, &b) if respond_to?(a.first)
    end
  end
end

class Environment
  attr_reader :type

  def initialize(type)
    case type
    when 'dev' then @type = :development
    when 'prod' then @type = :production
    when 'test' then @type = :test
    else
      raise 'unknown environment !'
    end
  end

  def dev?
    @type == :development
  end
  alias_method :development?, :dev?

  def prod?
    @type == :production
  end
  alias_method :production?, :prod?

  def test?
    @type == :test
  end
  alias_method :testing?, :test?

  def to_s
    @type.to_s
  end

  def [](key)
    ENV[key]
  end
end


class Loader
  public
  def load (dep, &block)
    if dep.kind_of? String
      load_bower(dep, &block)
    else
      load_object(dep, &block)
    end
  end

  private
  def load_object(dep)
    dep.each_pair do |key, value|
      case value
      # TODO need more support
      when Hash
        unless dep[key]['files'].nil?
          dep[key]['files'].each do |depjs|
            package_root = "bower_components/#{key}"
            package = "#{depjs}"
            yield package_root, package
          end
        end
      else
        return []
      end
    end
  end

  def load_bower(dep)
    file = "app/bower_components/#{dep}/bower.json"
    file = "app/bower_components/#{dep}/.bower.json" unless File.exist? file

    begin
      package_root = File.dirname(file).sub("app/", '')
      package = JSON.parse(File.read file)['main']
    rescue => e
      LOGGER.warn "#{file}: #{e.message}"
      return
    end

    if package.respond_to? :each
      package.each do |f|
        yield package_root, f
      end
    else
      yield package_root, package
    end
  end
end
LOADER = Loader.new

class LintTask < Rake::MultiTask
  # FIXME: should use the prerequesite.map(&:needed?) but
  # here, aFileTask.needed? return nil (wtf?)
  # Tmp fix: compiled_files array in declare_transform_tasks
  def needed?
    true
  end
end

# Given a transformation, declare automatically both method and task
def transform(from, opt, &block)
  opt.require [:to]

  if CONFIG['_known_types'].nil?
    CONFIG['_known_types'] = {}
  end
  CONFIG['_known_types'][from.to_s] = opt[:to].to_s unless opt[:no_package_transform]

  method_name = "compile_from_#{from}_to_#{opt[:to]}"
  define_method method_name.to_sym do |source, dest|
    dest_dir = File.dirname dest
    FileUtils.mkdir_p dest_dir unless Dir.exists? dest_dir
    block.call source, dest
  end

end

# Given transformation options, declare transformation by single task and batch
# task
def declare_transform_tasks(opts)
  opts.require [:from_type, :to_type, :from_dir, :to_dir, :glob]
  directory opts[:from_dir]
  directory opts[:to_dir]
  dir_dep = [opts[:from_dir], opts[:to_dir]]

  files = []
  compiled_files = [] # fix broken #needed? for Rake::FileTask
  pre_build = []
  post_build = []

  list = Rake::FileList.new opts[:glob]
  list.exclude opts[:exclude] if opts[:exclude].present?
  list.each do |f_src|
    f_dest = (f_src
          .sub(opts[:from_dir], opts[:to_dir])
          .sub(opts[:from_type].to_s, opts[:to_type].to_s))
    files << f_dest
    deps = [f_src]
    deps.concat pre_build unless pre_build.empty?

    Rake.application.define_task(Rake::FileTask, f_dest => deps) do
      compiled_files << deps.first
      send "compile_from_#{opts[:from_type]}_to_#{opts[:to_type]}", f_src, f_dest
      post_build.each do |task|
        Rake.application[task].invoke
      end
    end
  end

  if not opts[:lint].nil?
    lint = opts[:lint]
    if lint[:type].nil? || lint[:type] == :prebuild
      task_name = "pre_lint"
      pre_build << task_name
    else
      task_name = "post_lint"
      post_build << task_name
    end

    Rake.application.define_task(LintTask, task_name => files) do
      unless compiled_files.empty?
        # TODO merge in FMConfig
        bin = File.basename lint[:bin].to_s
        opts = (CONFIG[bin] || {})['options'] || []
        opts = opts.map{|e| '--' + e}.join ' '
        unless OS == 'Win' then
          sh "#{lint[:bin]} #{opts} #{compiled_files.join ' '}" do |ok|
            unless ok
              return false
            end
          end
        end
      end
    end

    dir_dep << task_name
  else
    dir_dep.concat files
  end

  desc "Build ALL the #{opts[:to_type]} files"
  multitask :all => dir_dep
end
