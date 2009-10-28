begin
  require 'cucumber/rake/task' #I have to add this
  require 'spec/rake/spectask'

  namespace :rcov do
    Cucumber::Rake::Task.new(:cucumber) do |t|
      t.rcov = true
      t.rcov_opts = %w{--rails --exclude osx\/objc,gems\/,spec\/,features\/ --aggregate coverage.data --sort=coverage}
      t.rcov_opts << %[-o "generated/coverage/features"]
    end

    desc "Run both specs and features to generate aggregated coverage"
    task :all do |t|
      rm "coverage.data" if File.exist?("coverage.data")
      Rake::Task["rcov:cucumber"].invoke
      Rake::Task["spec:rcov"].invoke
    end
  end
rescue LoadError
  namespace :rcov do
    desc 'rcov rake task not available (cucumber/rake not installed)'
    task :all do
      abort 'Rcov:all rake task is not available. Be sure to install rspec and cucumber as a gem or plugin'
    end
  end
end