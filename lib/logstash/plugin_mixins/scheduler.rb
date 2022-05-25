# encoding: utf-8

require 'logstash/namespace'
require 'logstash/plugin'
require 'logstash/util/thread_safe_attributes'

module LogStash
  module PluginMixins
    module Scheduler

      extend LogStash::Util::ThreadSafeAttributes

      ##
      # @private
      # @param base [Class]: a class that inherits `LogStash::Plugin`, typically one
      #                      descending from one of the four plugin base classes
      #                      (e.g., `LogStash::Inputs::Base`)
      # @raise [ArgumentError]
      # @return [void]
      def self.included(base)
        fail(ArgumentError, "`#{base}` must inherit LogStash::Plugin") unless base < LogStash::Plugin
        instance_methods = base.instance_methods
        base.send(:prepend, StopHook) if instance_methods.include?(:stop)
        base.send(:prepend, CloseHook) if instance_methods.include?(:close)
      end

      # @private
      module StopHook
        def stop
          release_scheduler! # wait till scheduler halts
          super # plugin.stop
        end
      end
      private_constant :StopHook

      # @private
      module CloseHook
        def close
          super # plugin.close
          release_scheduler
        end
      end
      private_constant :CloseHook

      # def scheduler(); @_scheduler ||= new_scheduler({}) end
      lazy_init_attr(:scheduler, variable: :@_scheduler) { start_scheduler({}) }

      # Release jobs registered by the plugin from executing.
      # This method executes from the plugin's #close method.
      def release_scheduler
        @_scheduler.shutdown if @_scheduler
      end

      # Release jobs registered by the plugin from executing.
      # This method executes from the plugin's #stop method.
      # @note Blocks until the scheduler operation completes!
      def release_scheduler!
        @_scheduler.shutdown! if @_scheduler
      end

      # @param opts [Hash] scheduler options
      # @return [SchedulerInterface] scheduler instance
      def start_scheduler(opts, name: nil)
        if name.nil?
          unless self.class.name
            raise ArgumentError, "can not generate a scheduler name for anonymous class: #{inspect}"
          end
          pipeline_id = (respond_to?(:execution_context) && execution_context&.pipeline_id) || 'main'
          plugin_name = self.class.name.split('::').last # e.g. "jdbc"
          name = "[#{pipeline_id}]|#{self.class.plugin_type}|#{plugin_name}|scheduler"
          # thread naming convention: [psql1]|input|jdbc|scheduler
        end
        # TODO: should we use plugin's logger in the scheduler?
        RufusImpl::SchedulerAdapter.new(name, opts)
      end
      private :start_scheduler

      # Scheduler interface usable by plugins.
      module SchedulerInterface

        # All scheduling methods return a `Scheduler::JobInterface`

        # @return a job object which responds to a #job_id method
        # @abstract
        def cron(schedule, opts = {}, &task); fail NotImplementedError end
        # @return a job object which responds to a #job_id method
        # @abstract
        def every(period, opts = {}, &task); fail NotImplementedError end
        # @return a job object which responds to a #job_id method
        # @abstract
        def at(timestamp, opts = {}, &task); fail NotImplementedError end
        # @return a job object which responds to a #job_id method
        # @abstract
        def in(delay, opts = {}, &task); fail NotImplementedError end
        # @return a job object which responds to a #job_id method
        # @abstract
        def interval(interval, opts = {}, &task); fail NotImplementedError; end

        # Remove a previously scheduled job, this is optional
        # and only relevant for a shared scheduler.
        # def delete_job(job); fail NotImplementedError; end

        # Blocks until _all_ jobs are joined, including jobs
        # that are scheduled after this join has begun blocking.
        # @abstract
        def join; fail NotImplementedError end

        # Is this scheduler paused?
        # Pausing is assumed to be optional feature.
        #
        # @return [true] if paused
        # @return [false] not paused - scheduler operating normally
        # @return [nil] if pausing is not supported
        # def paused?; nil end

        # Pause executing scheduled jobs.
        # @see #paused?
        # def pause; fail NotImplementedError end

        # Resume executing jobs.
        # def resume; end

        # Shutdown the scheduler:
        #  - prevents additional jobs from being registered,
        #  - and unschedules all future invocations of jobs previously registered
        #
        # This operation does not block until the scheduler stops.
        # @abstract
        def shutdown; fail NotImplementedError end

        # Shutdown the scheduler:
        #  - prevents additional jobs from being registered,
        #  - and unschedules all future invocations of jobs previously registered
        #
        # This operation does WAIT until the scheduler stops.
        # @abstract
        def shutdown!; fail NotImplementedError end

        # @abstract
        def shutdown?; fail NotImplementedError end

      end

      # Interface provided by a scheduled job.
      module JobInterface

        def job_id; fail NotImplementedError end

      end

    end
  end
end

require 'logstash/plugin_mixins/scheduler/rufus_impl'
