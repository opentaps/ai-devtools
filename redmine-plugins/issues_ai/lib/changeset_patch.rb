require_dependency 'changeset'

# Patches Redmine's Changesets dynamically.
module ChangesetPatch
  def self.included(base) # :nodoc:
    base.extend(ClassMethods)

    base.send(:include, InstanceMethods)

  end

  module ClassMethods

  end

  module InstanceMethods
    # Path to the review result file
    def code_review_results_path
      unless self.repository.nil? or self.repository.url.blank?
        return self.repository.url + '/code_review/results/' + self.identifier
      end
    end

    # Path to the review queue file
    def code_review_queue_path
      unless self.repository.nil? or self.repository.url.blank?
        return self.repository.url + '/code_review/queue/' + self.identifier
      end
    end

    # Check if the changeset has a code review in the queue, to do this check if the file exists
    def has_code_review_queued?
      path = code_review_queue_path
      return false if path.nil?
      File.exist?(path)
    end

    # Check if the changeset has code review results, to do this check if the file exists
    def has_code_review_results?
      path = code_review_results_path
      return false if path.nil?
      File.exist?(path)
    end

    # Return the code review results
    def code_review_results
      path = code_review_results_path
      return nil if path.nil?
      return nil unless File.exist?(path)
      File.read(path)
    end

    def queue_code_review
      path = code_review_queue_path
      return nil if path.nil?
      File.open(path, 'w') { |file| file.write(self.identifier) }
    end

    def save_code_review_results(results)
      path = code_review_results_path
      return nil if path.nil?
      File.open(path, 'w') { |file| file.write(results) }
    end
  end
end

# Apply the patch
Changeset.send(:include, ChangesetPatch)
