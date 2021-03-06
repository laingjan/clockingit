# The filters added to this controller will be run for all controllers in the application.
# Likewise will all the methods added be available for all controllers.
class ApplicationController < ActionController::Base
  include Misc
  include ExceptionNotifiable
  include DateAndTimeHelper

  helper :task_filter
  helper :users
  helper :date_and_time
  helper :todos
  helper :tags
  helper :time_tracking
  helper :resources

#  helper :all

  helper_method :last_active
  helper_method :render_to_string
  helper_method :current_user
  helper_method :tz
  helper_method :current_projects
  helper_method :current_project_ids
  helper_method :completed_milestone_ids
  helper_method :worked_nice
  helper_method :link_to_task
  helper_method :current_task_filter
  helper_method :current_templates

  before_filter :install
  before_filter :authorize, :except => [ :login, :validate, :signup, :take_signup, :forgotten_password,
                                         :take_forgotten, :show_logo, :about, :screenshots, :terms, :policy,
                                         :company_check, :subdomain_check, :unsubscribe,
                                         :igoogle_setup, :igoogle
                                       ]

#  before_filter :clear_cache

  after_filter :set_charset

#  protect_from_forgery :secret => '112141be0ba20082c17b05c78c63f357'

  def current_user
    unless @current_user
      @current_user = User.find(session[:user_id],
                                :include => [ :projects, { :company => :properties } ],
                                :conditions => ["projects.completed_at IS NULL"])
    end
    @current_user
  end

  def current_sheet
    unless @current_sheet
      @current_sheet = Sheet.find(:first, :conditions => ["user_id = ?", session[:user_id]], :order => 'sheets.id', :include => :task)
      unless @current_sheet.nil?
        if @current_sheet.task.nil?
          @current_sheet.destroy
          @current_sheet = nil
        end
      end
    end
    @current_sheet
  end

  def tz
    unless @tz
      @tz = Timezone.get(current_user.time_zone)
    end
    @tz
  end

  # Force UTF-8 for all text Content-Types
  def set_charset
    content_type = headers["Content-Type"] || 'text/html'
    if /^text\//.match(content_type)
      headers["Content-Type"] = "#{content_type}; charset=utf-8"
    end

  end

  # Send the current user to the install page
  def install
    if Company.count == 0
      redirect_to "/install" and return false
    end
  end

  # Make sure the session is logged in
  def authorize
    session[:history] ||= []

    # Remember the previous _important_ page for returning to after an edit / update.
    if( request.request_uri.include?('/list') || request.request_uri.include?('/search') || request.request_uri.include?('/edit_preferences') ||
        request.request_uri.include?('/timeline') || request.request_uri.include?('/gantt') ||
        request.request_uri.include?('/forums') || request.request_uri.include?('/topics') ) &&
        !request.xhr?
      session[:history] = [request.request_uri] + session[:history][0,3] if session[:history][0] != request.request_uri
    end

#    session[:user_id] = User.find(:first, :offset => rand(1000).to_i).id
#    session[:user_id] = 1

    logger.info("remember[#{session[:remember_until]}]")

    # We need to re-authenticate
    if session[:user_id] && session[:remember_until] && session[:remember_until] < Time.now.utc
      session[:user_id] = nil
      session[:remember_until] = nil
    end

    if session[:user_id].to_i == 0
      if !(request.request_uri.include?('/login/login') || request.xhr?)
        session[:redirect] = request.request_uri
      elsif session[:history] && session[:history].size > 0
        session[:redirect] = session[:history][0]
      end

      # Generate a javascript redirect if user timed out without requesting a new page
      if request.xhr?
        render :update do |page|
          page.redirect_to :controller => 'login', :action => 'login'
        end
      else
        redirect_to "/login/login"
      end
    else
      session[:remember_until] = Time.now.utc + ( session[:remember].to_i == 1 ? 1.month : 1.hour )

      current_sheet

      # Set current locale
      Localization.lang(current_user.locale || 'en_US')

      if session[:redirect]
        redirect_to session[:redirect]
        session[:redirect] = nil
      end
    end
    true
  end

  # Parse <tt>1w 2d 3h 4m</tt> or <tt>1:2:3:4</tt> => minutes or seconds
  def parse_time(input, minutes = false)
    TimeParser.parse_time(current_user, input, minutes)
  end

  # List of Users current Projects ordered by customer_id and Project.name
  def current_projects
    current_user.projects
  end


  # List of current Project ids, joined with ,
  def current_project_ids
    current_user.project_ids_for_sql
  end

  def all_projects
    current_user.all_projects
  end



  # List of completed milestone ids, joined with ,
  def completed_milestone_ids
    unless @milestone_ids
      @milestone_ids ||= Milestone.find(:all, :conditions => ["company_id = ? AND completed_at IS NOT NULL", current_user.company_id]).collect{ |m| m.id }.join(',')
      @milestone_ids = "-1" if @milestone_ids == ''
    end
    @milestone_ids
  end

  def worked_nice(minutes)
    format_duration(minutes, current_user.duration_format, current_user.workday_duration, current_user.days_per_week)
  end

  def highlight( text, k )
    t = text.gsub(/(#{Regexp.escape(k)})/i, '<strong>\1</strong>')
  end

  def highlight_all( text, keys )
    keys.each do |k|
      text = highlight(text, k)
    end
    text
  end

#  def rescue_action(exception)
#    log_exception(exception)
#    exception.is_a?(ActiveRecord::RecordInvalid) ? render_invalid_record(exception.record) : super
#  end

  def render_invalid_record(record)
    render :action => (record.new_record? ? 'new' : 'edit')
  end

  def admin?
    current_user.admin > 0
  end

  def logged_in?
    true
  end

  def last_active
    session[:last_active] ||= Time.now.utc
  end

  ###
  # Returns the list to use for auto completes for user names.
  ###
  def auto_complete_for_user_name
    text = params[:user]
    text = text[:name] if text

    @users = []
    if !text.blank?
      conds = Search.search_conditions_for([ text ])
      @users = current_user.company.users.find(:all, :conditions => conds)
    end

    render(:partial => "/users/auto_complete_for_user_name")
  end

  ###
  # Returns the list to use for auto completes for customer names.
  ###
  def auto_complete_for_customer_name
    text = params[:customer]
    text = text[:name] if text

    @customers = []
    if !text.blank?
      conds = Search.search_conditions_for([ text ])
      @customers = current_user.company.customers.find(:all, :conditions => conds)
    end

    render(:partial => "/clients/auto_complete_for_customer_name")
  end

  ###
  # Returns the layout to use to display the current request.
  # Add a "layout" param to the request to use a different layout.
  ###
  def decide_layout
    params[:layout] || "application"
  end

  ###
  # Which company does the served hostname correspond to?
  ###
  def company_from_subdomain
    if @company.nil?
      subdomain = request.subdomains.first if request.subdomains

      @company = Company.find(:first, :conditions => ["subdomain = ?", subdomain])
      if Company.count == 1
        @company ||= Company.find(:first, :order => "id asc")
      end
    end

    return @company
  end

  # Redirects to the last page this user was on.
  # If the current request is using ajax, uses js to do the redirect.
  # If the tutorial hasn't been completed, sends them back to that page
  def redirect_from_last
    url = "/activities/list" # default

    if session[:history] && session[:history].any?
      url = session[:history].first
    elsif !current_user.seen_welcome?
      url = "/activities/welcome"
    end

    url = url.gsub("format=js", "")
    redirect_using_js_if_needed(url)
  end

  private

  # Returns a link to the given task.
  # If highlight keys is given, that text will be highlighted in
  # the link.
  def link_to_task(task, truncate = true, highlight_keys = [])
    link = "<strong>#{task.issue_num}</strong> "
    if task.is_a? Template
      url = url_for(:id => task.task_num, :controller => 'task_templates', :action => 'edit')
    else
      url = url_for(:id => task.task_num, :controller => 'tasks', :action => 'edit')
    end
    title = task.to_tip(:duration_format => current_user.duration_format,
                        :workday_duration => current_user.workday_duration,
                        :days_per_week => current_user.days_per_week,
                        :user => current_user)
    title = highlight_all(title, highlight_keys)

    html = {
      :class => "tooltip tasklink #{task.css_classes}",
      :title => title
    }

    if @ajax_task_links
      html[:onclick] = "showTaskInPage(#{ task.task_num }); return false;"
    end

    text = truncate ? task.name : self.class.helpers.truncate(task.name, :length => 80)
    text = highlight_all(text, highlight_keys)

    link += self.class.helpers.link_to(text, url, html)
    return link
  end

  # returns the current task filter (or a new, blank one
  # if none set)
  def current_task_filter
    @current_task_filter ||= TaskFilter.system_filter(current_user)
  end

  # Redirects to the given url. If the current request is using ajax,
  # javascript will be used to do the redirect.
  def redirect_using_js_if_needed(url)
    url = url_for(url)

    if !request.xhr?
      redirect_to url
    else
      render(:update) { |page| page << "parent.document.location = '#{ url }'" }
    end
  end
  def current_templates
    Template.find(:all, :conditions=>[ "project_id IN (#{ current_project_ids }) AND company_id = ?", current_user.company_id ])
  end
end
