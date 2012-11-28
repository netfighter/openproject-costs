require File.expand_path(File.dirname(__FILE__) + "/../spec_helper.rb")

describe CostlogController do
  let (:project) { Factory.build(:project_with_trackers) }
  let (:issue) { Factory.build(:issue, :project => project,
                                       :author => user,
                                       :tracker => project.trackers.first) }
  let (:user) { Factory.build(:user) }
  let (:user2) { Factory.build(:user) }
  let (:controller) { Factory.build(:role, :permissions => [:log_costs, :edit_cost_entries]) }
  let (:cost_type) { Factory.build(:cost_type) }
  let (:cost_entry) { Factory.build(:cost_entry, :issue => issue,
                                                 :project => project,
                                                 :spent_on => Date.today,
                                                 :overridden_costs => 400,
                                                 :units => 100,
                                                 :user => user,
                                                 :comments => "") }
  let(:issue_status) { Factory.create(:issue_status, :is_default => true) }

  def grant_current_user_permissions user, permissions
    member = Factory.build(:member, :project => project,
                                    :principal => user)
    member.roles << Factory.build(:role, :permissions => permissions)
    member.principal = user
    member.save!
    user.reload # in order to refresh the member/membership associations
    User.stub!(:current).and_return(user)
  end

  def disable_flash_sweep
    @controller.instance_eval{flash.stub!(:sweep)}
  end

  shared_examples_for "assigns" do
    it { assigns(:cost_entry).project.should == expected_project }
    it { assigns(:cost_entry).issue.should == expected_issue }
    it { assigns(:cost_entry).user.should == expected_user }
    it { assigns(:cost_entry).spent_on.should == expected_spent_on }
    it { assigns(:cost_entry).cost_type.should == expected_cost_type }
    it { assigns(:cost_entry).units.should == expected_units }
    it { assigns(:cost_entry).overridden_costs.should == expected_overridden_costs }
  end

  before do
    # removing db entries added by fixtures
    # TODO: remove fixtures
    CostType.destroy_all
    CostEntry.destroy_all
    Project.destroy_all
    User.destroy_all
    Rate.destroy_all

    user.save!
    project.save!
    #issue_status
    issue.save! if issue
    disable_flash_sweep
    @controller.stub!(:check_if_login_required)
  end

  describe "GET new" do
    let(:params) { { "issue_id" => issue.id.to_s } }

    let(:expected_project) { project }
    let(:expected_issue) { issue }
    let(:expected_user) { user }
    let(:expected_spent_on) { Date.today }
    let(:expected_cost_type) { nil }
    let(:expected_overridden_costs) { nil }
    let(:expected_units) { nil }

    shared_examples_for "successful new" do
      before do
        get :new, params
      end

      it { response.should be_success }
      it_should_behave_like "assigns"
      it { response.should render_template('edit') }
    end

    shared_examples_for "forbidden new" do
      before do
        get :new, params
      end

      it { response.response_code.should == 403 }
    end

    describe "WHEN user allowed to create new cost_entry" do
      before do
        grant_current_user_permissions user, [:log_costs]
      end

      it_should_behave_like "successful new"
    end

    describe "WHEN user allowed to create new cost_entry
              WHEN a default cost_type exists" do
      let(:expected_cost_type) { cost_type }

      before do
        cost_type.default = true
        cost_type.save!

        grant_current_user_permissions user, [:log_costs]
      end

      it_should_behave_like "successful new"
    end

    describe "WHEN user is allowed to create new own cost_entry" do
      before do
        grant_current_user_permissions user, [:log_own_costs]
      end

      it_should_behave_like "successful new"
    end

    describe "WHEN user is not allowed to create new cost_entries" do
      before do
        grant_current_user_permissions user, []
      end

      it_should_behave_like "forbidden new"
    end
  end

  describe "GET edit" do
    let(:params) { { "id" => cost_entry.id.to_s } }

    before do
      cost_entry.save(false)
    end

    shared_examples_for "successful edit" do
      before do
        get :edit, params
      end

      it { response.should be_success }
      it { assigns(:cost_entry).should == cost_entry }
      it { assigns(:cost_entry).should_not be_changed }
      it { response.should render_template('edit') }
    end

    shared_examples_for "forbidden edit" do
      before do
        get :edit, params
      end

      it { response.response_code.should == 403 }
    end

    describe "WHEN the user is allowed to edit cost_entries" do
      before do
        grant_current_user_permissions user, [:edit_cost_entries]
      end

      it_should_behave_like "successful edit"
    end

    describe "WHEN the user is allowed to edit cost_entries
              WHEN trying to edit a not own cost_entry" do
      before do
        grant_current_user_permissions user, [:edit_cost_entries]

        cost_entry.user = Factory.create(:user)
        cost_entry.save(false)
      end

      it_should_behave_like "successful edit"
    end

    describe "WHEN the user is allowed to edit own cost_entries" do
      before do
        grant_current_user_permissions user, [:edit_own_cost_entries]
      end

      it_should_behave_like "successful edit"
    end

    describe "WHEN the user is allowed to edit own cost_entries
              WHEN trying to edit a not own cost_entry" do
      before do
        grant_current_user_permissions user, [:edit_own_cost_entries]

        cost_entry.user = Factory.create(:user)
        cost_entry.save(false)
      end

      it_should_behave_like "forbidden edit"
    end

    describe "WHEN the user is not allowed to edit cost_entries" do
      before do
        grant_current_user_permissions user, []
      end

      it_should_behave_like "forbidden edit"
    end

    describe "WHEN the user is allowed to edit cost_entries
              WHEN the cost_entry is associated to a different project" do
      before do
        grant_current_user_permissions user, [:edit_cost_entries]

        cost_entry.project = Factory.create(:project_with_trackers)
        cost_entry.issue = Factory.create(:issue, :project => cost_entry.project,
                                                  :tracker => cost_entry.project.trackers.first,
                                                  :author => user)
        cost_entry.save!
      end

      it_should_behave_like "forbidden edit"
    end

    describe "WHEN the user is allowed to edit cost_entries
              WHEN the provided id is invalid" do
      before do
        grant_current_user_permissions user, [:edit_cost_entries]

        params["id"] = (cost_entry.id + 1).to_s

        get :edit, params
      end

      it { response.response_code.should == 404 }
    end
  end

  describe "POST create" do
    let (:params) { { "project_id" => project.id.to_s,
                      "cost_entry" => { "user_id" => user.id.to_s,
                                        "issue_id" => (issue.present? ? issue.id.to_s : "") ,
                                        "units" => units.to_s,
                                        "cost_type_id" => (cost_type.present? ? cost_type.id.to_s : "" ),
                                        "comments" => "lorem",
                                        "spent_on" => date.to_s,
                                        "overridden_costs" => overridden_costs.to_s } } }
    let(:expected_project) { project }
    let(:expected_issue) { issue }
    let(:expected_user) { user }
    let(:expected_overridden_costs) { overridden_costs }
    let(:expected_spent_on) { date }
    let(:expected_cost_type) { cost_type }
    let(:expected_units) { units }

    let(:user2) { Factory.create(:user) }
    let(:date) { "2012-04-03".to_date }
    let(:overridden_costs) { 500.00 }
    let(:units) { 5.0 }

    before do
      cost_type.save! if cost_type.present?
    end

    shared_examples_for "successful create" do
      before do
        post :create, params
      end

      # is this really usefull, shouldn't it redirect to the creating issue by default?
      it { response.should redirect_to(:controller => "costlog", :action => "details", :project_id => project) }
      it { assigns(:cost_entry).should_not be_new_record }
      it_should_behave_like "assigns"
      it { flash[:notice].should eql I18n.t(:notice_successful_create) }
    end


    shared_examples_for "invalid create" do
      before do
        post :create, params
      end

      it { response.should be_success }
      it_should_behave_like "assigns"
      it { flash[:notice].should be_nil }
    end

    shared_examples_for "forbidden create" do
      before do
        post :create, params
      end

      it { response.response_code.should == 403 }
    end

    describe "WHEN the user is allowed to create cost_entries" do
      before do
        grant_current_user_permissions user, [:log_costs]
      end

      it_should_behave_like "successful create"
    end

    describe "WHEN the user is allowed to create cost_entries" do
      before do
        grant_current_user_permissions user, [:log_own_costs]
      end

      it_should_behave_like "successful create"
    end

    describe "WHEN the user is allowed to create cost_entries
              WHEN no date is specified" do
      let(:expected_spent_on) { Date.today }

      before do
        grant_current_user_permissions user, [:log_costs]

        params["cost_entry"].delete("spent_on")
      end

      it_should_behave_like "successful create"
    end

    describe "WHEN the user is allowed to create cost_entries
              WHEN a non existing cost_type_id is specified
              WHEN no default cost_type is defined" do

      let(:expected_cost_type) { nil }

      before do
        grant_current_user_permissions user, [:log_costs]
        params["cost_entry"]["cost_type_id"] = (cost_type.id + 1).to_s
      end

      it_should_behave_like "invalid create"
    end

    describe "WHEN the user is allowed to create cost_entries
              WHEN a non existing cost_type_id is specified
              WHEN a default cost_type is defined" do

      let(:expected_cost_type) { nil }

      before do
        Factory.create(:cost_type, :default => true)

        grant_current_user_permissions user, [:log_costs]
        params["cost_entry"]["cost_type_id"] = 1
      end

      it_should_behave_like "invalid create"
    end

    describe "WHEN the user is allowed to create cost_entries
              WHEN no cost_type is specified
              WHEN a default cost_type is defined" do

      let(:expected_cost_type) { nil }

      before do
        Factory.create(:cost_type, :default => true)

        grant_current_user_permissions user, [:log_costs]
        params["cost_entry"].delete("cost_type_id")
      end

      it_should_behave_like "invalid create"
    end

    describe "WHEN the user is allowed to create cost_entries
              WHEN no cost_type is specified
              WHEN no default cost_type is defined" do

      let(:expected_cost_type) { nil }

      before do
        grant_current_user_permissions user, [:log_costs]
        params["cost_entry"].delete("cost_type_id")
      end

      it_should_behave_like "invalid create"
    end

    describe "WHEN the user is allowed to create cost_entries
              WHEN the cost_type id provided belongs to an inactive cost_type" do

      before do
        grant_current_user_permissions user, [:log_costs]
        cost_type.deleted_at = Date.today
        cost_type.save!
      end

      it_should_behave_like "invalid create"
    end

    describe "WHEN the user is allowed to create cost_entries
              WHEN the user is allowed to log cost for someone else and is doing so
              WHEN the other user is a member of the project" do

      before do
        grant_current_user_permissions user, []
        grant_current_user_permissions user2, [:log_costs]

        params["cost_entry"]["user_id"] = user.id.to_s
      end

      it_should_behave_like "successful create"
    end

    describe "WHEN the user is allowed to create cost_entries
              WHEN the user is allowed to log cost for someone else and is doing so
              WHEN the other user isn't a member of the project" do

      before do
        grant_current_user_permissions user2, [:log_costs]

        params["cost_entry"]["user_id"] = user.id.to_s
      end

      it_should_behave_like "invalid create"
    end

    describe "WHEN the user is allowed to create cost_entries
              WHEN the id of an issue not included in the provided project is provided" do

      let(:project2) { Factory.create(:project_with_trackers) }
      let(:issue2) { Factory.create(:issue, :project => project2,
                                            :tracker => project2.trackers.first,
                                            :author => user) }
      let(:expected_issue) { issue2 }

      before do
        grant_current_user_permissions user, [:log_costs]

        params["cost_entry"]["issue_id"] = issue2.id
      end

      it_should_behave_like "invalid create"
    end

    describe "WHEN the user is allowed to create cost_entries
              WHEN no issue_id is provided" do

      let(:expected_issue) { nil }

      before do
        grant_current_user_permissions user, [:log_costs]

        params["cost_entry"].delete("issue_id")
      end

      it_should_behave_like "invalid create"
    end

    describe "WHEN the user is allowed to create cost_entries
              WHEN the user is not allowed to log cost for someone else and is trying to do so" do

      before do
        grant_current_user_permissions user2, [:log_own_costs]

        params["cost_entry"]["user_id"] = user.id
      end

      it_should_behave_like "forbidden create"
    end

    describe "WHEN the user is not allowed to create cost_entries" do

      before do
        grant_current_user_permissions user, []
      end

      it_should_behave_like "forbidden create"
    end
  end


  describe "PUT update" do
    let(:params) { { "id" => cost_entry.id.to_s,
                     "cost_entry" => { "comments" => "lorem",
                                       "issue_id" => cost_entry.issue.id.to_s,
                                       "units" => cost_entry.units.to_s,
                                       "spent_on" => cost_entry.spent_on.to_s,
                                       "user_id" => cost_entry.user.id.to_s,
                                       "cost_type_id" => cost_entry.cost_type.id.to_s } } }

    before do
      cost_entry.save(false)
    end

    let(:expected_issue) { cost_entry.issue }
    let(:expected_user) { cost_entry.user }
    let(:expected_project) { cost_entry.project }
    let(:expected_cost_type) { cost_entry.cost_type }
    let(:expected_units) { cost_entry.units }
    let(:expected_overridden_costs) { cost_entry.overridden_costs }
    let(:expected_spent_on) { cost_entry.spent_on }

    shared_examples_for "successful update" do
      before do
        put :update, params
      end

      it { response.should redirect_to(:controller => "costlog", :action => "details", :project_id => project) }
      it { assigns(:cost_entry).should == cost_entry }
      it_should_behave_like "assigns"
      it { assigns(:cost_entry).should_not be_changed }
      it { flash[:notice].should eql I18n.t(:notice_successful_update) }
    end

    shared_examples_for "invalid update" do
      before { put :update, params }

      it_should_behave_like "assigns"
      it { response.should be_success }
      it { flash[:notice].should be_nil }
    end

    shared_examples_for "forbidden update" do
      before do
        put :update, params
      end

      it { response.response_code.should == 403 }
    end

    describe "WHEN the user is allowed to update cost_entries
              WHEN updating:
                issue_id
                user_id
                units
                cost_type
                overridden_costs
                spent_on" do

      let(:expected_issue) { Factory.create(:issue, :project => project,
                                                    :tracker => project.trackers.first,
                                                    :author => user) }
      let(:expected_user) { Factory.create(:user) }
      let(:expected_spent_on) { cost_entry.spent_on + 4.days }
      let(:expected_units) { cost_entry.units + 20 }
      let(:expected_cost_type) { Factory.create(:cost_type) }
      let(:expected_overridden_costs) { cost_entry.overridden_costs + 300 }

      before do
        grant_current_user_permissions expected_user, []
        grant_current_user_permissions user, [:edit_cost_entries]

        params["cost_entry"]["issue_id"] = expected_issue.id.to_s
        params["cost_entry"]["user_id"] = expected_user.id.to_s
        params["cost_entry"]["spent_on"] = expected_spent_on.to_s
        params["cost_entry"]["units"] = expected_units.to_s
        params["cost_entry"]["cost_type_id"] = expected_cost_type.id.to_s
        params["cost_entry"]["overridden_costs"] = expected_overridden_costs.to_s
      end

      it_should_behave_like "successful update"
    end

    describe "WHEN the user is allowed to update cost_entries
              WHEN updating nothing" do

      before do
        grant_current_user_permissions user, [:edit_cost_entries]
      end

      it_should_behave_like "successful update"
    end

    describe "WHEN the user is allowed ot update own cost_entries
              WHEN updating something" do
      let(:expected_units) { cost_entry.units + 20 }

      before do
        grant_current_user_permissions user, [:edit_own_cost_entries]

        params["cost_entry"]["units"] = expected_units.to_s
      end

      it_should_behave_like "successful update"
    end

    describe "WHEN the user is allowed to update cost_entries
              WHEN updating the user
              WHEN the new user isn't a member of the project" do

      let(:user2) { Factory.create(:user) }
      let(:expected_user) { user2 }

      before do
        grant_current_user_permissions user, [:edit_cost_entries]

        params["cost_entry"]["user_id"] = user2.id.to_s
      end

      it_should_behave_like "invalid update"
    end

    describe "WHEN the user is allowed to update cost_entries
              WHEN updating the issue
              WHEN the new issue isn't an issue of the current project" do

      let(:project2) { Factory.create(:project_with_trackers) }
      let(:issue2) { Factory.create(:issue, :project => project2,
                                            :tracker => project2.trackers.first) }
      let(:expected_issue) { issue2 }

      before do
        grant_current_user_permissions user, [:edit_cost_entries]

        params["cost_entry"]["issue_id"] = issue2.id.to_s
      end

      it_should_behave_like "invalid update"
    end

    describe "WHEN the user is allowed to update cost_entries
              WHEN updating the issue
              WHEN the new issue_id isn't existing" do

      let(:expected_issue) { nil }

      before do
        grant_current_user_permissions user, [:edit_cost_entries]

        params["cost_entry"]["issue_id"] = (issue.id + 1).to_s
      end

      it_should_behave_like "invalid update"
    end


    describe "WHEN the user is allowed to update cost_entries
              WHEN updating the cost_type
              WHEN the new cost_type is deleted" do

      let(:expected_cost_type) { Factory.create(:cost_type, :deleted_at => Date.today) }

      before do
        grant_current_user_permissions user, [:edit_cost_entries]

        params["cost_entry"]["cost_type_id"] = expected_cost_type.id.to_s
      end

      it_should_behave_like "invalid update"
    end

    describe "WHEN the user is allowed to update cost_entries
              WHEN updating the cost_type
              WHEN the new cost_type doesn't exist" do

      let(:expected_cost_type) { nil }

      before do
        grant_current_user_permissions user, [:edit_cost_entries]

        params["cost_entry"]["cost_type_id"] = "1"
      end

      it_should_behave_like "invalid update"
    end

    describe "WHEN the user is allowed to update own cost_entries and not all
              WHEN updating own cost entry
              WHEN updating the user" do

      let(:user3) { Factory.create(:user) }

      before do
        grant_current_user_permissions user, [:edit_own_cost_entries]

        params["cost_entry"]["user_id"] = user3.id
      end

      it_should_behave_like "forbidden update"
    end

    describe "WHEN the user is allowed to update own cost_entries and not all
              WHEN updating foreign cost_entry
              WHEN updating someting" do

      let(:user3) { Factory.create(:user) }

      before do
        grant_current_user_permissions user3, [:edit_own_cost_entries]

        params["cost_entry"]["units"] = (cost_entry.units + 20).to_s
      end

      it_should_behave_like "forbidden update"
    end

  end
end
