#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require_dependency 'canvas'

module Canvas

  class NoPluginError < StandardError;end

  class Plugin
    @registered_plugins = {}
    
    attr_accessor :meta, :settings
    attr_reader :id, :tag

    def initialize(id, tag=nil)
      @id = id.to_s
      @tag = tag.to_s if tag
      @meta = {
              :name=>id.to_s.humanize,
              :description=>nil,
              :website=>nil,
              :author=>nil,
              :author_website=>nil,
              :version=>nil,
              :settings_partial=>nil,
              :settings=>nil,
              :encrypted_settings=>nil,
              :base=>nil
      }.with_indifferent_access
    end
    
    def default_settings
      @meta[:settings]
    end
    
    def saved_settings
      PluginSetting.settings_for_plugin(self.id, self)
    end
    
    def settings
      # TODO: once we have distributed memcache we can
      # cache this properly across all web servers
      saved_settings
    end

    def enabled?
      ps = PluginSetting.find_by_name(self.id.to_s)
      return false unless ps
      ps.valid_settings? && ps.enabled?
    end

    def encrypted_settings
      @meta[:encrypted_settings]
    end

    [:name, :description, :website, :author, :author_website].each do |method|
      class_eval <<-METHOD
        def #{method}
          t_if_proc(@meta[:#{method}]) || ''
        end
      METHOD
    end

    def setting(name)
      t_if_proc(settings[name])
    end

    def t_if_proc(attribute)
      attribute.is_a?(Proc) ? instance_eval(&attribute) : attribute
    end

    def validator
      @meta[:validator]
    end
    
    def version
      @meta[:version]
    end
    
    def settings_partial
      @meta[:settings_partial]
    end
    
    def has_settings_partial?
      !meta[:settings_partial].blank?
    end

    # base class/module for this plugin
    def base
      @meta[:base]
    end

    # arbitrary meta key/value pairs (these aren't configurable settings)
    def metadata(name)
      t_if_proc(@meta[name])
    end

    def translate(key, default, options={})
      key = "canvas.plugins.#{@id}.#{key}" unless key =~ /\A#/
      I18n.translate(key, default, options)
    end
    alias :t :translate

    # Let the plugin do any validations necessary.
    # If the plugin has defined a validator, call
    # the :validate method on that validator.  If it
    # doesn't return a hash then consider it a failure.
    # The validator receives the model so that it can
    # add any errors that it would like.
    def validate_settings(plugin_setting, settings)
      if validator
        validator_module = Canvas::Plugins::Validators.const_defined?(validator) && Canvas::Plugins::Validators.const_get(validator)
        if validator_module && validator_module.respond_to?(:validate)
          res = validator_module.validate(settings, plugin_setting)
          if res.is_a?(Hash)
            plugin_setting.settings = (self.default_settings || {}).with_indifferent_access.merge(res || {})
          else
            false
          end
        else
          plugin_setting.errors.add_to_base("provided validator #{validator} failed to load")
          false
        end
      else
        plugin_setting.settings = (self.default_settings || {}).with_indifferent_access.merge(settings || {})
      end
    end

    def self.register(id, tag=nil, meta={})
      raise "Id required for a plugin" if id.nil?
      p = Plugin.new(id, tag)
      p.meta.merge! meta
      @registered_plugins[p.id] = p
    end
    
    def self.all
      @registered_plugins.values.sort{|p,p2| p.name <=> p2.name}
    end

    def self.all_for_tag(tag)
      @registered_plugins.values.select{|p|p.tag == tag.to_s}.sort{|p,p2| p.name <=> p2.name}
    end

    def self.find(id)
      @registered_plugins[id.to_s] || nil
    end

    def self.find!(id)
      raise(NoPluginError) if id.nil?
      @registered_plugins[id.to_s] || raise(NoPluginError)
    end
  end
  
  module Plugins
    module Validators
    end
  end
end
