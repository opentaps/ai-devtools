require_dependency 'repository'

# Patches Redmine's Repository dynamically.
module RepositoryPatch
  def self.included(base) # :nodoc:
    base.extend(ClassMethods)

    base.send(:include, InstanceMethods)

  end

  module ClassMethods

  end

  module InstanceMethods
    # Path to the code review directory
    def code_review_path
      unless self.url.blank?
        return self.url + '/code_review/'
      end
    end

    # Path to the prompt for code reviews
    def code_review_prompt_path
      unless self.url.blank?
        return self.url + '/code_review/prompt.txt'
      end
    end
    # Path to the prompt for code reviews of multiple commits
    def code_review_prompt_multi_path
      unless self.url.blank?
        return self.url + '/code_review/prompt_multi.txt'
      end
    end

    # Path to the code review result directory
    def code_review_results_path
      unless self.url.blank?
        return self.url + '/code_review/results/'
      end
    end

    # Path to the code review queue directory
    def code_review_queue_path
      unless self.url.blank?
        return self.url + '/code_review/queue/'
      end
    end

    # Check if the repository has a code review prompt, to do this check if the file exists
    def has_code_review?
      path = code_review_path
      return false if path.nil?
      File.exist?(path)
    end

    # Get the current prompt
    def code_review_prompt
      path = code_review_prompt_path
      return nil if path.nil?
      return nil unless File.exist?(path)
      # return the file contents
      File.read(path)
    end
    # Set the current prompt
    def code_review_prompt=(prompt)
      path = code_review_prompt_path
      return nil if path.nil?
      File.open(path, 'w') { |file| file.write(prompt) }
    end

    # Get the current prompt for multiple commits
    def code_review_prompt_multi
      path = code_review_prompt_multi_path
      return nil if path.nil?
      return nil unless File.exist?(path)
      # return the file contents
      File.read(path)
    end
    # Set the current prompt for multiple commits
    def code_review_prompt_multi=(prompt_multi)
      path = code_review_prompt_multi_path
      return nil if path.nil?
      File.open(path, 'w') { |file| file.write(prompt_multi) }
    end
  end
end

# Apply the patch
Repository.send(:include, RepositoryPatch)
