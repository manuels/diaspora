class Pod < ActiveRecord::Base
  has_many :people
  serialize :supported_versions

  def self.find_or_create_by_url(url)
    u = URI.parse(url)
    pod = self.find_or_initialize_by_host(u.host)
    unless pod.persisted?
      pod.ssl = (u.scheme == 'https')? true : false
      pod.save
    end
    pod
  end

  # casts a xml representation (in PublicsController::NATIVE_VERSION) of an object
  # into the xml representation the pod is able to understand
  def cast(xml)
    target_version = (PublicsController::SUPPORTED_VERSIONS & self.supported_versions).first
    self.class.cast(xml, target_version)
  end

  def self.cast(xml, target_version)
    return xml if target_version == PublicsController::NATIVE_VERSION
#    return Base64.encode64s(xml) if target_version == PublicsController::NATIVE_VERSION

    raise "not implemented yet"
  end
end
