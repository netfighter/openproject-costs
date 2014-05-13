#-- copyright
# OpenProject Costs Plugin
#
# Copyright (C) 2009 - 2014 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#++

# Prevent load-order problems in case openproject-plugins is listed after a plugin in the Gemfile
# or not at all
require 'open_project/plugins'

module OpenProject::Costs
  class Engine < ::Rails::Engine
    engine_name :openproject_costs

    include OpenProject::Plugins::ActsAsOpEngine

    register 'openproject-costs',
             :author_url => 'http://finn.de',
             :requires_openproject => '>= 3.0.0',
             :settings =>  { :default => { 'costs_currency' => 'EUR','costs_currency_format' => '%n %u' },
             :partial => 'settings/openproject_costs' } do

      project_module :costs_module do
        permission :view_own_hourly_rate, {}
        permission :view_hourly_rates, {}

        permission :edit_own_hourly_rate, {:hourly_rates => [:set_rate, :edit, :update]},
                                          :require => :member
        permission :edit_hourly_rates, {:hourly_rates => [:set_rate, :edit, :update]},
                                       :require => :member
        permission :view_cost_rates, {} # cost item values

        permission :log_own_costs, { :costlog => [:new, :create] },
                                   :require => :loggedin
        permission :log_costs, {:costlog => [:new, :create]},
                               :require => :member

        permission :edit_own_cost_entries, {:costlog => [:edit, :update, :destroy]},
                                           :require => :loggedin
        permission :edit_cost_entries, {:costlog => [:edit, :update, :destroy]},
                                       :require => :member

        permission :view_cost_objects, {:cost_objects => [:index, :show]}

        permission :view_cost_entries, { :cost_objects => [:index, :show], :costlog => [:index] }
        permission :view_own_cost_entries, { :cost_objects => [:index, :show], :costlog => [:index] }

        permission :edit_cost_objects, {:cost_objects => [:index, :show, :edit, :update, :destroy, :new, :create, :copy]}
      end

      # register additional permissions for the time log
      project_module :time_tracking do
        permission :view_own_time_entries, {:timelog => [:index, :report]}
      end

      # Menu extensions
      menu :top_menu,
           :cost_types,
           {:controller => '/cost_types', :action => 'index'},
           :caption => :cost_types_title,
           :if => Proc.new { User.current.admin? }

      menu :project_menu,
           :cost_objects,
           {:controller => '/cost_objects', :action => 'index'},
           :param => :project_id,
           :before => :settings,
           :caption => :cost_objects_title,
           :html => {:class => 'icon2 icon-budget'}

      menu :project_menu,
           :new_budget,
           {:controller => '/cost_objects', :action => 'new' },
           :param => :project_id,
           :caption => :label_cost_object_new,
           :parent => :cost_objects,
           :html => {:class => 'icon2 icon-add'}

      menu :project_menu,
           :show_all,
           {:controller => '/cost_objects', :action => 'index' },
           :param => :project_id,
           :caption => :label_view_all_cost_objects,
           :parent => :cost_objects,
           :html => {:class => 'icon2 icon-list-view1'}

      Redmine::Activity.map do |activity|
        activity.register :cost_objects, class_name: 'Activity::CostObjectActivityProvider', default: false
      end
    end

    patches [:WorkPackage, :Project, :Query, :User, :TimeEntry, :Version, :PermittedParams,
             :ProjectsController, :ApplicationHelper, :UsersHelper]

    assets %w(costs/costs.css costs/costs.js)

    initializer "costs.register_hooks" do
      require 'open_project/costs/hooks'
      require 'open_project/costs/hooks/activity_hook'
      require 'open_project/costs/hooks/work_package_hook'
      require 'open_project/costs/hooks/project_hook'
      require 'open_project/costs/hooks/work_package_action_menu'
      require 'open_project/costs/hooks/work_packages_show_attributes'
    end

    initializer 'costs.register_observers' do |app|
      # Observers
      ActiveRecord::Base.observers.push :rate_observer, :default_hourly_rate_observer, :costs_work_package_observer
    end

    initializer 'costs.patch_number_helper' do |app|
      # we have to do the patching in the initializer to make sure we only do this once in development
      # since the NumberHelper is not unloaded
      ActionView::Helpers::NumberHelper.send(:include, OpenProject::Costs::Patches::NumberHelperPatch)
    end

    config.to_prepare do
      # loading the class so that acts_as_journalized gets registered
      VariableCostObject

      # TODO: this recreates the original behaviour
      # however, it might not be desirable to allow assigning of cost_object regardless of the permissions
      PermittedParams.permit(:new_work_package, :cost_object_id)
    end
  end
end


