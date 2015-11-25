
require 'rake'
require 'rake/testtask'

Rake::TaskManager.record_task_metadata = true

require 'bundler/gem_tasks'

Rake::TestTask.new do |t|
  #t.warning = true
  t.verbose = true
  t.libs << "spec"
  t.test_files = FileList['spec/**/*_spec.rb']
end

# Set default task to list all task
desc 'Default task (build)'
task :default do
  puts 'Usage : rake <taskname>'
  puts ''

  Rake::application.options.show_tasks = :tasks  # this solves sidewaysmilk problem
  Rake::application.options.show_task_pattern = //
  Rake::application.display_tasks_and_comments
end

