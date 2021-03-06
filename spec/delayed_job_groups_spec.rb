require 'spec/spec_helper'

ActiveRecord::Schema.define do
  create_table :grouped_jobs, :force => true do |table|
    table.string :repository
  end
  create_table :simple_jobs, :force => true do |table|
  end
  create_table :users, :force => true do |table|
    table.string :role
  end
end

class GroupedJob < ActiveRecord::Base
  job_group{ |simple_job| simple_job.repository }

  def perform
    puts "running grouped job"
  end
end

class SimpleJob < ActiveRecord::Base
  def perform
    puts "running simple job"
  end
end

class StandaloneJob < Struct.new :name
  include JobGroup
  job_group{ |standalone_job| standalone_job.name }  
  
  def perform
    puts "running standalone job"
  end
end

class User < ActiveRecord::Base
  job_group{ |user| user.role }  
  def send_welcome_email
    puts "thanking user"
  end
  handle_asynchronously :send_welcome_email  
  def expensive_operation
    puts "working hard"
  end
end

describe Delayed::Job do
  MAX_RUN_TIME = 4000 # seconds? TBC
  WORKER = 'name_of_worker'
  
  context "a job" do
    before do
      Delayed::Job.enqueue GroupedJob.new(:repository => "repo1")
    end
    
    it "should have a job group" do
      Delayed::Job.first.lock_group.should == "repo1"
    end
  end
  
  context "a standalone job" do
    before do
      Delayed::Job.enqueue StandaloneJob.new("repo1")
    end
    
    it "should have a job group" do
      Delayed::Job.first.lock_group.should == "repo1"
    end
  end
  
  context "with 2 jobs in the same group, one locked, one unlocked and 1 job in a different group" do
    before do
      2.times{ Delayed::Job.enqueue GroupedJob.new(:repository => "repo1") }
      1.times{ Delayed::Job.enqueue GroupedJob.new(:repository => "repo2") }
      Delayed::Job.first.lock_exclusively!(MAX_RUN_TIME, WORKER)      
    end
    
    it "should find no jobs that are ready to run" do
      Delayed::Job.ready_to_run(WORKER, MAX_RUN_TIME).count.should == 1
    end
  end
  
  context "job with no group" do
    before do
      Delayed::Job.enqueue SimpleJob.new
    end
    it "should still be queuable" do
      Delayed::Job.ready_to_run(WORKER, MAX_RUN_TIME).count.should == 1
    end
  end
  
  context "with 2 jobs in the same group, from methods declared as asynchronous, one unlocked and 1 job in a different group" do
    before do
      2.times do
        User.create(:role => "admin").send_welcome_email
      end
      1.times{ Delayed::Job.enqueue GroupedJob.new(:repository => "repo2") }      
      Delayed::Job.first.lock_exclusively!(MAX_RUN_TIME, WORKER)
      
    end
    
    it "should find no jobs that are ready to run" do
      Delayed::Job.ready_to_run(WORKER, MAX_RUN_TIME).count.should == 1
    end
  end

  context "with 2 jobs in the same group (one timed out), from methods declared as asynchronous, one unlocked and 1 job in a different group" do
    before do
      2.times do
        User.create(:role => "admin").send_welcome_email
      end
      1.times{ Delayed::Job.enqueue GroupedJob.new(:repository => "repo2") }      
      Delayed::Job.first.lock_exclusively!(MAX_RUN_TIME, WORKER)
      Delayed::Job.first.update_attributes :locked_at => (Time.now - MAX_RUN_TIME.days)
    end
    
    it "should find all jobs are available to run" do
      Delayed::Job.ready_to_run(WORKER, MAX_RUN_TIME).count.should == 3
    end
  end
  
  context "with 2 jobs in the same group, from delay() calls, one unlocked and 1 job in a different group" do
    before do
      2.times do
        User.create(:role => "admin").delay.expensive_operation
      end
      1.times{ Delayed::Job.enqueue GroupedJob.new(:repository => "repo2") }      
      Delayed::Job.first.lock_exclusively!(MAX_RUN_TIME, WORKER)
      
    end
    
    it "should find no jobs that are ready to run" do
      Delayed::Job.ready_to_run(WORKER, MAX_RUN_TIME).count.should == 1
    end
  end

  context "with 2 jobs in the same group (one timed out), from delay() calls, one unlocked and 1 job in a different group" do
    before do
      2.times do
        User.create(:role => "admin").delay.expensive_operation
      end
      1.times{ Delayed::Job.enqueue GroupedJob.new(:repository => "repo2") }
			Delayed::Job.first.lock_exclusively!(MAX_RUN_TIME, WORKER)
			Delayed::Job.first.update_attributes :locked_at => (Time.now - MAX_RUN_TIME.days)
    end
    
    it "should find all jobs are available to run" do
      Delayed::Job.ready_to_run(WORKER, MAX_RUN_TIME).count.should == 3
    end
  end 
end