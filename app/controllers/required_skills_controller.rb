class RequiredSkillsController < ApplicationController
  unloadable
  
  before_filter :load_model
  before_filter :authorize, :except => ['assign_user']
  
  include SkillsMatcherHelper

  def add
    @action = params[:required_skill][:action]
    name = params[:required_skill][:name]
    skill = Skill.find_by_name(name)
    unless skill
      # Allow users to create new skills on the fly via this form
      skill = Skill.new(:name => name)
      skill.save!
    end
    level = params[:required_skill][:level].to_i
    @required_skill = RequiredSkill.new(:issue => @issue, :skill => skill, :level => level)

    unless @issue.assigned_to.nil? || @action == "force"
      config = SkillsProjectConfig.find_by_project_id(@project.id)
      if !config.nil? && config.validate_assignments?
        @issue.required_skills << @required_skill
        unless user_is_qualified? @issue.assigned_to, @issue
          if config.block_assignments?
            @action = "block"
          else
            @action = "warn"
          end
          @issue.required_skills.delete @required_skill
        end
      end
    end

    unless @action == "block" || @action == "warn"
      if @required_skill.save
        @required_skill = nil
      end
    end
    refresh_required_skills
  end

  def remove
    @required_skill = RequiredSkill.find(params[:id])
    @required_skill.destroy
    @required_skill = nil
    refresh_required_skills
  rescue ActiveRecord::RecordNotFound
    render_404
  end
  
  def assign_user
    # TODO: check permissions
    user = User.find(params[:issue][:assigned_to_id])
    unless (params[:membership].nil?)
      @membership = Member.new(:principal => user)
      @membership.attributes = params[:membership]
      @membership.project = @project
      if @membership.save
        flash[:notice] = l(:notice_add_memberships_success, :name => user.login) + "<br/>"
      else
        flash[:error] = l(:notice_add_memberships_failure, :name => user.login) + "<br/>"
      end
    end
    if @issue.project.assignable_users.include? user
      # Unfortunately, I wasn't able to find a way to submit the change here and reuse all
      # IssuesController logic without doing a redirect, which requires a second manual form submit.
      #flash[:notice] = l(:notice_successful_assignment, :name => user.login)
      flash[:notice] += l(:notice_confirm_assignment, :name => user.login)
      redirect_to :controller => 'issues', :action => 'update', :id => @issue, :issue => { :assigned_to_id => user.id }
      return
    end
    flash[:error] += l(:notice_unsuccessful_assignment, :name => user.login)
    redirect_to :controller => 'skills_matcher', :action => :find_users_for_issue, :issue_id => @issue
  end

  private 
  
  def load_model
    issue_id = params[:issue_id] || params[:required_skill][:issue_id]
    @issue = Issue.find(issue_id)
    @project = @issue.project
  end
  
  def refresh_required_skills
    respond_to do |format|
      format.js do
        render :update do |page|
            page.replace_html "required_skills", :partial => "required_skills"
        end
      end
    end
  end
  
end