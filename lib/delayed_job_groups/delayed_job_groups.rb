require 'delayed_job'

class Delayed::Backend::ActiveRecord::Job
  scope :in_unlocked_group, lambda{ |max_run_time|
    delayed_jobs = self.table_name
    unlocked_groups_select = "select distinct #{delayed_jobs}.lock_group from #{delayed_jobs} where #{delayed_jobs}.locked_by is not null and locked_at > ?"
    where(["#{delayed_jobs}.lock_group not in (#{unlocked_groups_select}) or #{delayed_jobs}.lock_group is null", db_time_now - max_run_time])
  }
  scope :orig_ready_to_run, scopes[:ready_to_run]
  scope :ready_to_run, lambda{ |worker_name, max_run_time|
    orig_ready_to_run(worker_name, max_run_time).
    in_unlocked_group(max_run_time)
  }

	
  def unlock
    self.lock_group   = nil
    super
  end
end