require 'chkbuild'

require 'fileutils'

require "util"
require 'chkbuild/target'
require 'chkbuild/build'

begin
  Process.setpriority(Process::PRIO_PROCESS, 0, 10)
rescue Errno::EACCES # already niced to 11 or more
end

File.umask(002)
STDIN.reopen("/dev/null", "r")
STDOUT.sync = true

class Build
  @target_list = []
  def Build.main
    Build.lock_start
    @target_list.each {|t|
      t.make_result
    }
  end

  def Build.def_target(target_name, *args, &block)
    t = ChkBuild::Target.new(target_name, *args, &block)
    @target_list << t
    t
  end

  class << Build
    attr_accessor :num_oldbuilds
  end
  Build.num_oldbuilds = 3

  DefaultLimit = {
    :cpu => 3600 * 4,
    :stack => 1024 * 1024 * 40,
    :data => 1024 * 1024 * 100,
    :as => 1024 * 1024 * 100
  }

  def self.limit(hash)
    DefaultLimit.update(hash)
  end

  @upload_hook = []
  def self.add_upload_hook(&block)
    @upload_hook << block
  end
  def self.run_upload_hooks(suffixed_name)
    @upload_hook.reverse_each {|block|
      begin
        block.call suffixed_name
      rescue Exception
        p $!
      end
    }
  end

  TOP_DIRECTORY = Dir.getwd

  FileUtils.mkpath ChkBuild.build_dir
  LOCK_PATH = "#{ChkBuild.build_dir}/.lock"

  def Build.lock_start
    if !defined?(@lock_io)
      @lock_io = open(LOCK_PATH, File::WRONLY|File::CREAT)
    end
    if @lock_io.flock(File::LOCK_EX|File::LOCK_NB) == false
      raise "another chkbuild is running."
    end
    @lock_io.truncate(0)
    @lock_io.sync = true
    @lock_io.close_on_exec = true
    @lock_io.puts "locked pid:#{$$}"
    lock_pid = $$
    at_exit {
      @lock_io.puts "exit pid:#{$$}" if $$ == lock_pid
    }
  end

  def Build.lock_puts(mesg)
    @lock_io.puts mesg
  end
end
