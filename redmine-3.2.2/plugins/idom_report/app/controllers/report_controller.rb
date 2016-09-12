class ReportController < ApplicationController
  unloadable

  def work_time_report
    find_project
    authorize
    prepare_values
    member_add_del_check
    calc_total
  end

  private
  def find_project
    # Redmine Pluginとして必要らしいので@projectを設定
    @project = Project.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def prepare_values
    # ************************************* 値の準備
    @today = Date.today
    year = params.key?(:year) ? params[:year].to_i : @today.year
    month = params.key?(:month) ? params[:month].to_i : @today.month
    day = params.key?(:day) ? params[:day].to_i : @today.day

    @restrict_project = (params.key?(:prj) && params[:prj].to_i > 0) ? params[:prj].to_i : false
    @first_date = params.key?(:first_date) ? Date.parse(params[:first_date]) : @today
    @last_date = params.key?(:last_date) ? Date.parse(params[:last_date]) : @today
    
    @link_params = {:controller=>"report", :id=>@project.id,
                    :first_date=>@first_date, :last_date=>@last_date,
                    :prj=>@restrict_project, :action=>'work_time_report'}

    puts @link_params
    @is_registerd_backlog = false
    begin
      Redmine::Plugin.find :redmine_backlogs
      @is_registerd_backlog = true
    rescue Exception => exception
    end
  end

  def calc_total
    ################################################  合計集計計算ループ ########
    @total_cost = 0
    @member_cost = Hash.new
    WtMemberOrder.where(["prj_id=:p",{:p=>@project.id}]).all.each do |i|
      @member_cost[i.user_id] = 0
    end
    @issue_parent = Hash.new # clear cash
    @issue_cost = Hash.new
    @r_issue_cost = Hash.new
    relay = Hash.new
    WtTicketRelay.all.each do |i|
      relay[i.issue_id] = i.parent
    end
    @prj_cost = Hash.new
    @r_prj_cost = Hash.new

    #当月の時間記録を抽出
    TimeEntry.
        where(["spent_on>=:t1 and spent_on<=:t2 and hours>0",{:t1 => @first_date, :t2 => @last_date}]).
        all.
        each do |time_entry|
      iid = time_entry.issue_id
      uid = time_entry.user_id
      cost = time_entry.hours
      # 本プロジェクトのユーザの工数でなければパス
      next unless @member_cost.key?(uid)

      issue = Issue.find_by_id(iid)
      next if issue.nil? # チケットが削除されていたらパス
      pid = issue.project_id
      # プロジェクト限定の対象でなければパス
      next if @restrict_project && pid != @restrict_project

      @total_cost += cost
      @member_cost[uid] += cost

      parent_iid = get_parent_issue(relay, iid)
      if !Issue.find_by_id(iid) || !Issue.find_by_id(iid).visible?
        iid = -1 # private
        pid = -1 # private
      end
      @issue_cost[iid] ||= Hash.new
      @issue_cost[iid][-1] ||= 0
      @issue_cost[iid][-1] += cost
      @issue_cost[iid][uid] ||= 0
      @issue_cost[iid][uid] += cost

      @prj_cost[pid] ||= Hash.new
      @prj_cost[pid][-1] ||= 0
      @prj_cost[pid][-1] += cost
      @prj_cost[pid][uid] ||= 0
      @prj_cost[pid][uid] += cost

      parent_issue = Issue.find_by_id(parent_iid)
      if parent_issue && parent_issue.visible?
        parent_pid = parent_issue.project_id
      else
        parent_iid = -1
        parent_pid = -1
      end

      @r_issue_cost[parent_iid] ||= Hash.new
      @r_issue_cost[parent_iid][-1] ||= 0
      @r_issue_cost[parent_iid][-1] += cost
      @r_issue_cost[parent_iid][uid] ||= 0
      @r_issue_cost[parent_iid][uid] += cost

      @r_prj_cost[parent_pid] ||= Hash.new
      @r_prj_cost[parent_pid][-1] ||= 0
      @r_prj_cost[parent_pid][-1] += cost
      @r_prj_cost[parent_pid][uid] ||= 0
      @r_prj_cost[parent_pid][uid] += cost
    end
  end

  def get_parent_issue(relay, iid)
    @issue_parent ||= Hash.new
    return @issue_parent[iid] if @issue_parent.has_key?(iid)
    issue = Issue.find_by_id(iid)
    return 0 if issue.nil? # issueが削除されていたらそこまで
    @issue_cost[iid] ||= Hash.new

    if relay.has_key?(iid)
      parent_id = relay[iid]
      if parent_id != 0 && parent_id != iid
        parent_id = get_parent_issue(relay, parent_id)
      end
      parent_id = iid if parent_id == 0
    else
      # 関連が登録されていない場合は登録する
      WtTicketRelay.create(:issue_id=>iid, :position=>relay.size, :parent=>0)
      parent_id = iid
    end

    # iid に対する初めての処理
    pid = issue.project_id
    unless @prj_cost.has_key?(pid)
      check = WtProjectOrders.where(["uid=-1 and dsp_prj=:p",{:p=>pid}]).all
      if check.size == 0
        WtProjectOrders.create(:uid=>-1, :dsp_prj=>pid, :dsp_pos=>@prj_cost.size)
      end
    end

    @issue_parent[iid] = parent_id # return
  end

  def member_add_del_check
    # プロジェクトのメンバーを取得
    mem = Member.where(["project_id=:prj", {:prj=>@project.id}]).all
    mem_by_uid = {}
    mem.each do |m|
      mem_by_uid[m.user_id] = m
    end

    # メンバーの順序を取得
    odr = WtMemberOrder.where(["prj_id=:p", {:p=>@project.id}]).order("position").all

    # 当月のユーザ毎の工数入力数を取得
    entry_count = TimeEntry.
        where(["spent_on>=:first_date and spent_on<=:last_date",
               {:first_date=>@first_date, :last_date=>@last_date}]).
        select("user_id, count(hours)as cnt").
        group("user_id").
        all
    cnt_by_uid = {}
    entry_count.each do |ec|
      cnt_by_uid[ec.user_id] = ec.cnt
    end

    @members = []
    pos = 1
    # 順序情報にあってメンバーに無いものをチェック
    odr.each do |o|
      if mem_by_uid.has_key?(o.user_id) then
        user=mem_by_uid[o.user_id].user
        if ! user.nil? then
          # 順位の確認と修正
          if o.position != pos then
            o.position=pos
            o.save
          end
          # 表示メンバーに追加
          if user.active? || cnt_by_uid.has_key?(user.id) then
            @members.push([pos, user])
          end
          pos += 1
          # 順序情報に存在したメンバーを削っていく
          mem_by_uid.delete(o.user_id)
          next
        end
      end
      # メンバーに無い順序情報は削除する
      o.destroy
    end

    # 残ったメンバーを順序情報に加える
    mem_by_uid.each do |k,v|
      user = v.user
      next if user.nil?
      n = WtMemberOrder.new(:user_id=>user.id,
                              :position=>pos,
                              :prj_id=>@project.id)
      n.save
      if user.active? || cnt_by_uid.has_key?(user.id) then
        @members.push([pos, user])
      end
      pos += 1
    end
    
  end

end
