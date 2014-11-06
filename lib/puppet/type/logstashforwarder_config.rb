file_defined = false
if Object.const_defined?("Puppet")
  konst = Object.const_get("Puppet")
  if (konst.const_defined?("Type"))
    file_defined = konst.const_get("Type").const_defined?("File")
  end
end

Puppet::Type.newtype(:logstashforwarder_config) do
  @doc = "Collects any elasticsearch nodes for unicast and merges that with the hash config given in 'config_hash'
  This is created to allow auto collecting of all unicast nodes without having to work with file concat
  "

  ensurable

  # the file/posix provider will check for the :links property
  # which does not exist
  def [](value)
    if value == :links
      return false
    end

    super
  end

  newparam(:name, :namevar => true) do
    desc "Resource name"
  end

  newparam(:path) do
    desc "The output file"
    defaultto do
      resource.value(:name)
    end
  end

  newparam(:tag) do
    desc "Tag reference to collect all file fragments with the same tag"
  end

  newproperty(:owner, :parent => Puppet::Type::File::Owner) do
    desc "Desired file owner."
    defaultto 'root'
  end

  newproperty(:group, :parent => Puppet::Type::File::Group) do
    desc "Desired file group."
    defaultto 'root'
  end

  newproperty(:mode, :parent => Puppet::Type::File::Mode) do
    desc "Desired file mode."
    defaultto '0644'
  end

  newparam(:config) do
    desc "config"
  end

  newproperty(:content) do
    desc "Read only attribute. Represents the content."

    include Puppet::Util::Diff
    include Puppet::Util::Checksums

    defaultto do
      # only be executed if no :content is set
      @content_default = true
      @resource.no_content
    end

    validate do |val|
      fail "read-only attribute" if !@content_default
      #fail Puppet::ParseError, "Required setting 'config' missing" if self[:config].nil?
    end

    def insync?(is)
      result = super

      if ! result
        string_file_diff(@resource[:path], @resource.should_content)
      end

      result
    end

    def is_to_s(value)
      md5(value)
    end

    def should_to_s(value)
      md5(value)
    end
  end

  def no_content
    "\0## GENERATED BY PUPPET ##\0"
  end

  def should_content
    return @generated_content if @generated_content
    @generated_content = ""
    fragment_content = []

    # Collect all config fragments nodes
    catalog.resources.select do |r|
      r.is_a?(Puppet::Type.type(:logstashforwarder_fragment)) && r[:tag] == self[:tag]
    end.each do |r|
       fragment_content << r[:content]
    end

    @generated_content = self[:config]+"\n  \"files\": [\n"+fragment_content.sort.join(",\n")+"\n  ]\n}"

    @generated_content
  end

  def stat(dummy_arg = nil)
    return @stat if @stat and not @stat == :needs_stat
    @stat = begin
      ::File.stat(self[:path])
    rescue Errno::ENOENT => error
      nil
    rescue Errno::EACCES => error
      warning "Could not stat; permission denied"
      nil
    end
  end

  ### took from original type/file
  # There are some cases where all of the work does not get done on
  # file creation/modification, so we have to do some extra checking.
  def property_fix
    properties.each do |thing|
      next unless [:mode, :owner, :group].include?(thing.name)

      # Make sure we get a new stat object
      @stat = :needs_stat
      currentvalue = thing.retrieve
      thing.sync unless thing.safe_insync?(currentvalue)
    end
  end
end
