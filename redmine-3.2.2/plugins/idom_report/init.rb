Redmine::Plugin.register :idom_report do
  name 'Idom Report plugin'
  author 'Hoang VoXuan'
  description 'This is plugin for Redmine to report in idom'
  version '0.0.1'

  permission :idom_report, { :report => [:index, :vote, :work_time_report] }, :public => true

  menu :project_menu, :idom_report, { :controller => 'report', :action => 'work_time_report' }, :caption => 'レポート',
   :after => :work_time

end
