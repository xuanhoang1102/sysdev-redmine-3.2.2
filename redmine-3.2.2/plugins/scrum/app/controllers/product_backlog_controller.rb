# Copyright © Emilio González Montaña
# Licence: Attribution & no derivates
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivates of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class ProductBacklogController < ApplicationController

  menu_item :product_backlog
  model_object Issue

  before_filter :find_project_by_project_id,
                :only => [:index, :sort, :new_pbi, :create_pbi, :burndown, :check_dependencies]
  before_filter :find_product_backlog,
                :only => [:index, :render_pbi, :sort, :new_pbi, :create_pbi, :burndown, :check_dependencies]
  before_filter :find_pbis, :only => [:index, :sort]
  before_filter :check_issue_positions, :only => [:index]
  before_filter :authorize

  helper :scrum

  def index
  end

  def sort
    @pbis.each do |pbi|
      pbi.init_journal(User.current)
      pbi.position = params["pbi"].index(pbi.id.to_s) + 1
      if Scrum::Setting.check_dependencies_on_pbi_sorting
        dependencies = get_dependencies(pbi)
        if dependencies.count > 0
          raise "PBI ##{pbi.id} depends on other PBIs (#{dependencies.collect{|p| "##{p.id}"}.join(", ")}), it cannot be sorted"
        end
      end
      pbi.save!
    end
    render :nothing => true
  end

  def check_dependencies
    @pbis_dependencies = get_dependencies
    respond_to do |format|
      format.js
    end
  end

  def new_pbi
    @pbi = Issue.new
    @pbi.project = @project
    @pbi.author = User.current
    @pbi.tracker = @project.trackers.find(params[:tracker_id])
    @pbi.sprint = @product_backlog
    respond_to do |format|
      format.html
      format.js
    end
  end

  def create_pbi
    begin
      @continue = !(params[:create_and_continue].nil?)
      @pbi = Issue.new(params[:issue])
      @pbi.project = @project
      @pbi.author = User.current
      @pbi.sprint = @product_backlog
      @pbi.save!
      @pbi.story_points = params[:issue][:story_points]
    rescue Exception => @exception
    end
    respond_to do |format|
      format.js
    end
  end

  def burndown
    @data = []
    @project.sprints.each do |sprint|
      @data << {:axis_label => sprint.name,
                :story_points => sprint.story_points.round(2),
                :pending_story_points => 0}
    end
    velocity_all_pbis, velocity_scheduled_pbis, @sprints_count = @project.story_points_per_sprint
    @velocity_type = params[:velocity_type] || "only_scheduled"
    case @velocity_type
      when "all"
        @velocity = velocity_all_pbis
      when "only_scheduled"
        @velocity = velocity_scheduled_pbis
      else
        @velocity = params[:custom_velocity].to_f unless params[:custom_velocity].blank?
    end
    @velocity = 1.0 if @velocity.blank? or @velocity < 1.0
    pending_story_points = @project.product_backlog.story_points
    new_sprints = 1
    while pending_story_points > 0
      @data << {:axis_label => "#{l(:field_sprint)} +#{new_sprints}",
                :story_points => ((@velocity <= pending_story_points) ?
                    @velocity : pending_story_points).round(2),
                :pending_story_points => 0}
      pending_story_points -= @velocity
      new_sprints += 1
    end
    for i in 0..(@data.length - 1)
      others = @data[(i + 1)..(@data.length - 1)]
      @data[i][:pending_story_points] = (@data[i][:story_points] +
        (others.blank? ? 0 : others.collect{|other| other[:story_points]}.sum)).round(2)
      @data[i][:story_points_tooltip] = l(:label_pending_story_points,
                                          :pending_story_points => @data[i][:pending_story_points],
                                          :sprint => @data[i][:axis_label],
                                          :story_points => @data[i][:story_points])
    end
  end

private

  def find_product_backlog
    @product_backlog = @project.product_backlog
    if @product_backlog.nil?
      render_error l(:error_no_product_backlog)
    end
  rescue
    render_404
  end

  def find_pbis
    @pbis = @product_backlog.pbis
  rescue
    render_404
  end

  def check_issue_positions
    check_issue_position(Issue.where(:sprint_id => @project.product_backlog, :position => nil))
  end

  def check_issue_position(issue)
    if issue.is_a?(Issue)
      if issue.position.nil?
        issue.reset_positions_in_list
        issue.save!
        issue.reload
      end
    elsif issue.respond_to?(:each)
      issue.each do |i|
        check_issue_position(i)
      end
    else
      raise "Invalid type: #{issue.inspect}"
    end
  end

  def get_dependencies(pbi = nil)
    dependencies = []
    if pbi
      @product_backlog.pbis(:position_bellow => pbi.position).each do |other_pbi|
        dependencies << other_pbi if pbi.all_dependent_issues.include?(other_pbi)
      end
    else
      @product_backlog.pbis.each do |a_pbi|
        pbi_dependencies = get_dependencies(a_pbi)
        dependencies << {:pbi => a_pbi, :dependencies => pbi_dependencies} if pbi_dependencies.count > 0
      end
    end
    return dependencies
  end

end
