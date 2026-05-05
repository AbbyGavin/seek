# bundle exec rake seek_hu:create_me
require 'net/http'
require 'URI'
require 'json'



namespace :seek_hu do

  task create_institution: :environment do
    url = "https://fairdomhub.org/institutions.json"
    response = Net::HTTP.get(URI(url))
    organizations = JSON.parse(response)["data"]
    disable_authorization_checks do
      organizations.each do |org|
        begin
          seek_title = org["attributes"]["title"]
          puts seek_title
          unless (Institution.where(title: seek_title).exists?)
            org = Institution.new(title: seek_title)
            if org.save!
              puts "Institution '#{org.title}' created successfully."
            else
              puts org.errors.full_messages.join(', ')
            end
          end
        rescue StandardError => e
          puts "An error occurred: #{e.message}"
        end
      end
    end
  end

  task create_extended_metadata_type: :environment do

    file = File.read('/Users/whomingbird/work/code/rails-projects/seek/filestore/uploaded_emt_files/emt_simple.json')
    data = JSON.parse(file)


    # Initialize a new ExtendedMetadataType with the title, supported_type, and enabled status from the JSON data
    emt = ExtendedMetadataType.new(
      title: data['title'],
      supported_type: data['supported_type'],
      enabled: data['enabled']
    )

    # Iterate over each attribute in the JSON data
    data['attributes'].each do |attr|
      # Find the SampleAttributeType based on the attribute_type from JSON
      sample_attribute_type = SampleAttributeType.where(title: attr['attribute_type']).first


      emt.extended_metadata_attributes.build(
        title: attr['title'],
        label: attr['label'],
        description: attr['description'],
        sample_attribute_type: sample_attribute_type,
        required: attr['required']
      )
    end

    # Attempt to save the ExtendedMetadataType along with its associated attributes
    puts "_______________________________________________"
    if emt.save
      puts "ExtendedMetadataType '#{emt.title}' created successfully."
    else
      puts "Failed to create ExtendedMetadataType: #{emt.errors.full_messages.join(', ')}"
    end
    puts "_______________________________________________"


  end

  task create_me: :environment do
    disable_authorization_checks do
      me = Person.create!(first_name:"Xiaoming",last_name:"Hu",email:"xiaoming.hu@h-its.com")
      user = User.create!(login: "huxg", person_id:me.id, password: "99iloveniuniu11", password_confirmation: "99iloveniuniu11")

      user.activate
      me.is_admin = true

      institution = Institution.create!(title: "Heidelberg Institute for Theoretical Studies", country:"Germany",
                                        city: "Heidelberg", web_page:"http://www.h-its.org/")

      project = Project.create!(title: "Scientific Databases and Visualization",
                                description: "Our mission is to improve data storage and the search for life science data, making storage, search,
                                              and processing simple to use for domain experts who are not computer scientists. We believe that much can be learned from running actual systems
                                               and serving their users, who can then tell us what is important for them.", web_page:"https://www.h-its.org/research/sdbv/")


      me.group_memberships << GroupMembership.create!(project:project,institution:institution)



      investigation = Investigation.create!(title:"My Investigation", contributor:me, project_ids: [project.id])
      investigation.policy.access_type = Policy::VISIBLE
      investigation.save!

      study = Study.create!(title:"My Study", description:"A complex study for color", contributor:me, investigation: investigation )
      study.policy.access_type = Policy::VISIBLE
      study.save!



      # LDH specific


      p1 = Person.create!(first_name: "Maciej", last_name:"Rosolowski",email:"m.r@example.com")
      p2 = Person.create!(first_name: "René", last_name:"Hänsel",email:"r.h@example.com")


      ldh_project = Project.create!(title: "LIFE HNC - Head and Neck Cancer Group",
                                    description: "The aim of the Head and Neck Group within the Leipzig Research Center for Civilization Diseases (LIFE) is to facilitate improvements in the treatment and care of head and neck cancer patients through insights from molecular studies.

The Head and Neck Group within the Leipzig Research Center for Civilization Diseases (LIFE) investigates the molecular mechanisms and the diagnostic and prognostic factors of head and neck cancer. For this purpose, we collected phenotypic information from about 300 patients and determined molecular profiles of their tumor specimen.

Sponsors are : Leipzig Research Center for Civilization Diseases (LIFE) University Leipzig European Union, the European Fund for Regional Development (EFRE) Free State of Saxony", web_page:"https://www.health-atlas.de/projects/7")

      me.group_memberships << GroupMembership.create!(project:ldh_project,institution:institution)

      title = "head and neck squamous cell carcinomas"
      desc = "Stratification of head and neck squamous cell carcinomas (HNSCC) based on HPV16 DNA and RNA status"

      ldh_investigation = Investigation.create!(title:title, description:desc, contributor:me, project_ids: [ldh_project.id])
      ldh_investigation.policy.access_type = Policy::VISIBLE
      ldh_investigation.save!

      title = "HNSCC"
      desc = "Stratification of head and neck squamous cell carcinomas (HNSCC) based on HPV16 DNA and RNA status"

      ldh_study = Study.create!(title:title, description:desc,contributor:me, investigation: ldh_investigation )
      ldh_study.policy.access_type = Policy::VISIBLE
      ldh_study.creators << p1
      ldh_study.creators << p2
      ldh_study.save!
    end
  end




  task create_user: :environment do
    disable_authorization_checks do

      (1...5).each do |num|
        password = "#{num}#{num}#{num}#{num}#{num}#{num}#{num}#{num}#{num}#{num}"
        guest = Person.create!(first_name: "guest#{num}", last_name:"test",email:"guest#{num}@example.com")
        user = User.create!(login: "guest#{num}", person_id:guest.id, password: password, password_confirmation: password)
        user.activate

        project= Project.find(2)
        institution = Institution.where(title:"Heidelberg Institute for Theoretical Studies").first
        unless guest.nil? || institution.nil?
          guest.add_to_project_and_institution(project, institution)
          guest.save!
        end
      end
    end
  end


  task create_user_and_their_resources: :environment do
    disable_authorization_checks do

      (1...5).each do |num|
        password = "#{num}" * 10

        guest = Person.create!(
          first_name: "guest#{num}",
          last_name: "test",
          email: "guest#{num}@example.com"
        )

        user = User.create!(
          login: "guest#{num}",
          person_id: guest.id,
          password: password,
          password_confirmation: password
        )
        user.activate

        project = Project.create!(title: "project guest#{num}")
        institution = Institution.where(title: "Heidelberg Institute for Theoretical Studies").first

        if guest && institution
          guest.add_to_project_and_institution(project, institution)
          guest.save!
        end

        # ============================================================
        # Create NO_ACCESS Investigation + Study for this guest user
        # ============================================================

        investigation = Investigation.create!(
          title: "Guest#{num} Investigation",
          contributor: guest,
          project_ids: [project.id]
        )

        investigation.policy.update!(
          access_type: Policy::NO_ACCESS,
          permissions: []
        )
        investigation.save!

        study = Study.create!(
          title: "Guest#{num} Study",
          description: "A study created for guest#{num}",
          contributor: guest,
          investigation: investigation
        )

        study.policy.update!(
          access_type: Policy::NO_ACCESS,
          permissions: []
        )
        study.save!

        puts "Created guest#{num} with NO_ACCESS investigation + study"
      end
    end
  end




  task create_project: :environment do
    disable_authorization_checks do
      (1..3).each do |num|
        project= Project.create!(title: generate_random_string )
        person = Person.where(first_name:"Xiaoming").first
        institution = Institution.where(title:"Heidelberg Institute for Theoretical Studies").first

        unless person.nil? || institution.nil?
          person.add_to_project_and_institution(project, institution)
          person.save!
        end

      end

    end
  end

  task create_programme: :environment do
    disable_authorization_checks do
      (1..2).each do |num|
        programme= Programme.create!(title: "programme #{num}" )
        programme.projects << Project.find(num)
        # programme.projects << Project.find(num*4)
      end
    end
  end


  task check_types_is_asset: :environment do
    all_types = Seek::Util.authorized_types
    all_types.each do |type|
      pp type.name + ".is_asset? =>" + type.is_asset?.inspect
    end
  end

  def valid_sharing
    {
      access_type: Policy::VISIBLE,
      permissions_attributes: {}
    }
  end

  def hidden_sharing
    {
      access_type: Policy::NO_ACCESS,
      permissions_attributes: {}
    }
  end

  def generate_random_string
    length = rand(5..7)
    characters = ('a'..'z').to_a + ('A'..'Z').to_a
    random_string = Array.new(length) { characters.sample }.join
    return random_string
  end

end
