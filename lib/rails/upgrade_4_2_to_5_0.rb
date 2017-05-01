Synvert::Rewriter.new 'rails', 'upgrade_4_2_to_5_0' do
  description <<-EOF
1. it replaces config.static_cache_control = ... with config.public_file_server.headers = ... in config files.

2. it replaces config.serve_static_files = ... with config.public_file_server.enabled = ... in config files.

3. it replaces render nothing: true with head :ok in controller files.

4. it replaces head status: 406 with head 406 in controller files.

5. it replaces middleware.use "Foo::Bar" with "middleware.use Foo::Bar" in config files.

6. it replaces redirect_to :back with redirect_back in controller files.

7. it replaces after_commit :xxx, on: :yyy with after_yyy_commit :xxx in model files.

8. it adds app/models/application_record.rb file.

9. it replaces ActiveRecord::Base with ApplicationRecord in model files.

10. it adds app/jobs/application_job.rb file.

11. it replaces ActiveJob::Base with ApplicationJob in job files.

12. it replaces MissingSourceFile with LoadError.

13. it adds config/initializers/new_framework_defaults.rb
  EOF

  within_files 'config/environments/*.rb' do
    # config.static_cache_control = 'public, max-age=31536000'
    # =>
    # config.public_file_server.headers = 'public, max-age=31536000'
    with_node type: 'send', message: 'static_cache_control=' do
      replace_with "{{receiver}}.public_file_server.headers = {{arguments}}"
    end

    # config.serve_static_files = true
    # =>
    # config.public_file_server.enabled = true
    with_node type: 'send', message: 'serve_static_files=' do
      replace_with "{{receiver}}.public_file_server.enabled = {{arguments}}"
    end

    # config.middleware.use "Foo::Bar"
    # =>
    # config.middleware.use Foo::Bar
    with_node type: 'send', receiver: {type: 'send', receiver: 'config', message: 'middleware'}, message: 'use', arguments: {first: {type: "str"}} do
      arguments_source = node.arguments.map(&:to_source)
      arguments_source[0] = node.arguments.first.to_value
      replace_with "{{receiver}}.{{message}} #{arguments_source.join(', ')}"
    end
  end

  within_file 'app/controllers/**/*.rb' do
    # render nothing: true
    # =>
    # head :ok
    with_node type: 'send', receiver: nil, message: 'render', arguments: { size: 1, first: { type: 'hash', keys: ['nothing'], values: [true] } } do
      replace_with "head :ok"
    end

    # head status: 406
    # head location: '/foo'
    # =>
    # head 406
    # head :ok, location: '/foo'
    with_node type: 'send', receiver: nil, message: 'head', arguments: { size: 1, first: { type: 'hash' } } do
      if node.arguments.first.has_key? :status
        replace_with "head {{arguments.first.values.first}}"
      else
        replace_with "head :ok, {{arguments}}"
      end
    end

    # redirect_to :back
    # =>
    # redirect_back
    with_node type: 'send', receiver: nil, message: 'redirect_to', arguments: [:back] do
      replace_with "redirect_back"
    end
  end

  # adds file app/models/application_record.rb
  new_code = "class ApplicationRecord < ActiveRecord::Base\n"
  new_code << "  self.abstract_class = true\n"
  new_code << "end"
  add_file 'app/models/application_record.rb', new_code

  within_files 'app/models/**/*.rb' do
    # after_commit :add_to_index_later, on: :create
    # after_commit :update_in_index_later, on: :update
    # after_commit :remove_from_index_later, on: :destroy
    # =>
    # after_create_commit :add_to_index_later
    # after_update_commit :update_in_index_later
    # after_detroy_commit :remove_from_index_later
    with_node type: 'send', receiver: nil, message: 'after_commit', arguments: {size: 2} do
      action = node.arguments.last.values.first.to_value
      replace_with "after_#{action}_commit {{arguments.first}}"
    end

    # class Post < ActiveRecord::Base
    # end
    # =>
    # class Post < ApplicationRecord
    # end
    with_node type: 'class', name: {not: 'ApplicationRecord'}, parent_class: 'ActiveRecord::Base' do
      goto_node :parent_class do
        replace_with "ApplicationRecord"
      end
    end
  end

  # adds file app/jobs/application_job.rb
  new_code = "class ApplicationJob < ActiveJob::Base\n\nend"
  add_file 'app/jobs/application_job.rb', new_code

  within_files 'app/jobs/**/*.rb' do
    # class PostJob < ActiveJob::Base
    # end
    # =>
    # class PostJob < ApplicationJob
    # end
    with_node type: 'class', name: {not: 'ApplicationJob'}, parent_class: 'ActiveJob::Base' do
      goto_node :parent_class do
        replace_with "ApplicationJob"
      end
    end
  end

  within_files '**/*.rb' do
    # MissingSourceFile
    # =>
    # LoadError
    with_node type: 'const', to_source: 'MissingSourceFile' do
      replace_with 'LoadError'
    end
  end

  new_code = """
# Be sure to restart your server when you modify this file.
#
# This file contains migration options to ease your Rails 5.0 upgrade.
#
# Read the Guide for Upgrading Ruby on Rails for more info on each option.

# Enable per-form CSRF tokens. Previous versions had false.
Rails.application.config.action_controller.per_form_csrf_tokens = true

# Enable origin-checking CSRF mitigation. Previous versions had false.
Rails.application.config.action_controller.forgery_protection_origin_check = true

# Make Ruby 2.4 preserve the timezone of the receiver when calling `to_time`.
# Previous versions had false.
ActiveSupport.to_time_preserves_timezone = true

# Require `belongs_to` associations by default. Previous versions had false.
Rails.application.config.active_record.belongs_to_required_by_default = true

# Do not halt callback chains when a callback returns false. Previous versions had true.
ActiveSupport.halt_callback_chains_on_return_false = false

# Configure SSL options to enable HSTS with subdomains. Previous versions had false.
Rails.application.config.ssl_options = { hsts: { subdomains: true } }
  """.strip
  add_file 'config/initializers/new_framework_defaults.rb', new_code
end