require File.expand_path '../test_helper.rb', __FILE__

include Rack::Test::Methods

def app
  ServiceBrokerApp.new
end

describe "get /v2/catalog" do
  def make_request
    get "/v2/catalog"
  end

  describe "when basic auth credentials are missing" do
    before do
      make_request
    end

    it "returns a 401 unauthorized response" do
      assert_equal 401, last_response.status
    end
  end

  describe "when basic auth credentials are incorrect" do
    before do
      authorize "admin", "wrong-password"
      make_request
    end

    it "returns a 401 unauthorized response" do
      assert_equal 401, last_response.status
    end
  end

  describe "when basic auth credentials are correct" do
    before do
      authorize "admin", "password"
      make_request
    end

    it "returns a 200 OK response" do
      assert_equal 200, last_response.status
    end

    it "specifies the content type of the response" do
      last_response.header["Content-Type"].must_include("application/json")
    end

    it "returns correct keys in JSON" do
      response_json = JSON.parse last_response.body

      response_json.keys.must_equal ["services"]

      services = response_json["services"]
      assert services.length > 0

      services.each do |service|
        assert_operator service.keys.length, :>=, 5
        assert service.keys.include? "id"
        assert service.keys.include? "name"
        assert service.keys.include? "description"
        assert service.keys.include? "bindable"
        assert service.keys.include? "plans"

        plans = service["plans"]
        assert plans.length > 0
        plans.each do |plan|
          assert_operator plan.keys.length, :>=, 3
          assert plan.keys.include? "id"
          assert plan.keys.include? "name"
          assert plan.keys.include? "description"
        end
      end
    end

    it "contains proper metadata when it is (optionally) provided in settings.yml" do
      response_json = JSON.parse last_response.body

      services = response_json["services"]

      services.each do |service|
        assert service.keys.include? "metadata"

        plans = service["plans"]
        plans.each do |plan|
          assert plan.keys.include? "metadata"
          plan_costs = plan["metadata"]["costs"]
          plan_costs.each do |cost|
            assert cost.keys.include? "amount"
            assert cost.keys.include? "unit"
            assert cost["amount"].keys.include? "usd"
          end
        end
      end
    end
  end
end

describe "put /v2/service_instances/:id" do
  before do
    @id = "1234-5678"
  end

  def make_request
    put "/v2/service_instances/#{@id}"
  end

  describe "when basic auth credentials are missing" do
    before do
      make_request
    end

    it "returns a 401 unauthorized response" do
      assert_equal 401, last_response.status
    end
  end

  describe "when basic auth credentials are incorrect" do
    before do
      authorize "admin", "wrong-password"
      make_request
    end

    it "returns a 401 unauthorized response" do
      assert_equal 401, last_response.status
    end
  end

  describe "when basic auth credentials are correct" do
    before do
      authorize "admin", "password"

      @fake_github_service = mock
      GithubServiceHelper.stubs(:new).returns(@fake_github_service)
    end

    describe "when repo is successfully created" do
      before do
        @fake_github_service.stubs(:create_github_repo).with("github-service-1234-5678").returns("http://some.repository.url")
        make_request
      end

      it "returns '201 Created'" do
        assert_equal 201, last_response.status
      end

      it "specifies the content type of the response" do
        last_response.header["Content-Type"].must_include("application/json")
      end

      it "returns json representation of dashboard URL" do
        expected_json = {
            "dashboard_url" => "http://some.repository.url"
        }.to_json

        assert_equal expected_json, last_response.body
      end
    end

    describe "when the repo already exists" do
      before do
        @fake_github_service.stubs(:create_github_repo).with("github-service-1234-5678").raises GithubServiceHelper::RepoAlreadyExistsError
        make_request
      end

      it "returns '409 Conflict'" do
        assert_equal 409, last_response.status
      end

      it "returns a JSON response explaining the error" do
        expected_json = {
            "description" => "The repo github-service-#{@id} already exists in the GitHub account"
        }.to_json

        assert_equal expected_json, last_response.body
      end
    end

    describe "when GitHub is not reachable" do
      before do
        @fake_github_service.stubs(:create_github_repo).with("github-service-1234-5678").raises GithubServiceHelper::GithubUnreachableError
        make_request
      end

      it "returns 504 Gateway Timeout" do
        assert_equal 504, last_response.status
      end

      it "returns a JSON response explaining the error" do
        expected_json = {
            "description" => "GitHub is not reachable"
        }.to_json

        assert_equal expected_json, last_response.body
      end
    end

    describe "when GitHub returns any other error" do
      before do
        @fake_github_service.stubs(:create_github_repo).with("github-service-1234-5678").raises GithubServiceHelper::GithubError.new("some message")
        make_request
      end

      it "returns 502 Bad Gateway" do
        assert_equal 502, last_response.status
      end

      it "returns a JSON response explaining the error" do
        expected_json = {
            "description" => "some message"
        }.to_json

        assert_equal expected_json, last_response.body
      end
    end
  end
end

describe "put /v2/service_instances/:instance_id/service_bindings/:id" do
  before do
    @instance_id = "1234"
    @binding_id = "5556"
  end

  def make_request
    put "/v2/service_instances/#{@instance_id}/service_bindings/#{@binding_id}"
  end

  describe "when basic auth credentials are missing" do
    before do
      make_request
    end

    it "returns a 401 unauthorized response" do
      assert_equal 401, last_response.status
    end
  end

  describe "when basic auth credentials are incorrect" do
    before do
      authorize "admin", "wrong-password"
      make_request
    end

    it "returns a 401 unauthorized response" do
      assert_equal 401, last_response.status
    end
  end

  describe "when basic auth credentials are correct" do
    before do
      authorize "admin", "password"

      @fake_github_service = mock
      GithubServiceHelper.stubs(:new).returns(@fake_github_service)
      @fake_github_service.stubs(:create_github_deploy_key)
    end

    it "specifies the content type of the response" do
      make_request
      last_response.header["Content-Type"].must_include("application/json")
    end

    describe "when binding succeeds" do
      before do
        @fake_github_service.expects(:create_github_deploy_key).with(repo_name: "github-service-#{@instance_id}", deploy_key_title: @binding_id).
            returns(
            {
                uri: "http://fake.github.com/some-user/some-repo",
                private_key: "private-key"
            }
        )
      end

      it "returns a 201 Created" do
        make_request
        assert_equal 201, last_response.status
      end

      it "responds with credentials, including the private key and repo url" do
        make_request
        last_response.body.must_equal({
                                          credentials: {
                                              uri: "http://fake.github.com/some-user/some-repo",
                                              private_key: "private-key"
                                          }
                                      }.to_json)
      end
    end

    describe "when the binding with the id already exists" do
      before do
        @fake_github_service.expects(:create_github_deploy_key).with(repo_name: "github-service-#{@instance_id}", deploy_key_title: @binding_id).
            raises GithubServiceHelper::BindingAlreadyExistsError
        make_request
      end

      it "returns '409 Conflict'" do
        assert_equal 409, last_response.status
      end

      it "returns a JSON response explaining the error" do
        expected_json = {
            "description" => "The binding #{@binding_id} already exists"
        }.to_json

        assert_equal expected_json, last_response.body
      end
    end

    describe "when GitHub resource is not found" do
      before do
        @fake_github_service.expects(:create_github_deploy_key).with(repo_name: "github-service-#{@instance_id}", deploy_key_title: @binding_id).
            raises GithubServiceHelper::GithubResourceNotFoundError
        make_request
      end

      it "returns 404 Not Found" do
        assert_equal 404, last_response.status
      end

      it "returns a JSON response explaining the error" do
        expected_json = {
            "description" => "GitHub resource not found"
        }.to_json

        assert_equal expected_json, last_response.body
      end
    end

    describe "when GitHub is not reachable" do
      before do
        @fake_github_service.expects(:create_github_deploy_key).with(repo_name: "github-service-#{@instance_id}", deploy_key_title: @binding_id).
            raises GithubServiceHelper::GithubUnreachableError
        make_request
      end

      it "returns 504 Gateway Timeout" do
        assert_equal 504, last_response.status
      end

      it "returns a JSON response explaining the error" do
        expected_json = {
            "description" => "GitHub is not reachable"
        }.to_json

        assert_equal expected_json, last_response.body
      end
    end

    describe "when GitHub returns any other error" do
      before do
        @fake_github_service.expects(:create_github_deploy_key).with(repo_name: "github-service-#{@instance_id}", deploy_key_title: @binding_id).
            raises GithubServiceHelper::GithubError.new("some message")
        make_request
      end

      it "returns 502 Bad Gateway" do
        assert_equal 502, last_response.status
      end

      it "returns a JSON response explaining the error" do
        expected_json = {
            "description" => "some message"
        }.to_json

        assert_equal expected_json, last_response.body
      end
    end
  end
end

describe "delete /v2/service_instances/:instance_id/service_bindings/:id" do
  before do
    @instance_id = "1234"
    @binding_id = "5556"
  end

  def make_request
    delete "/v2/service_instances/#{@instance_id}/service_bindings/#{@binding_id}"
  end

  describe "when basic auth credentials are missing" do
    before do
      make_request
    end

    it "returns a 401 unauthorized response" do
      assert_equal 401, last_response.status
    end
  end

  describe "when basic auth credentials are incorrect" do
    before do
      authorize "admin", "wrong-password"
      make_request
    end

    it "returns a 401 unauthorized response" do
      assert_equal 401, last_response.status
    end
  end

  describe "when basic auth credentials are correct" do
    before do
      authorize "admin", "password"

      @fake_github_service = mock
      GithubServiceHelper.stubs(:new).returns(@fake_github_service)
      @fake_github_service.stubs(:remove_github_deploy_key)
    end

    it "specifies the content type of the response" do
      make_request
      last_response.header["Content-Type"].must_include("application/json")
    end

    describe "when unbinding succeeds" do
      before do
        @fake_github_service.expects(:remove_github_deploy_key).
            with(repo_name: "github-service-#{@instance_id}", deploy_key_title: @binding_id).
            returns(true)

        make_request
      end

      it "returns a 200 OK" do
        assert_equal 200, last_response.status
      end

      it "returns an empty JSON body" do
        make_request
        last_response.body.must_equal("{}")
      end
    end

    describe "when unbinding fails" do
      describe "because binding id not found" do
        before do
          @fake_github_service.expects(:remove_github_deploy_key).
              with(repo_name: "github-service-#{@instance_id}", deploy_key_title: @binding_id).
              returns(false)

          make_request
        end

        it "returns a 410 Not found" do
          assert_equal 410, last_response.status
        end

        it "returns an empty JSON body" do
          make_request
          last_response.body.must_equal("{}")
        end
      end

      describe "because GitHub resource is not found" do
        before do
          @fake_github_service.expects(:remove_github_deploy_key).
              with(repo_name: "github-service-#{@instance_id}", deploy_key_title: @binding_id).
              raises(GithubServiceHelper::GithubResourceNotFoundError)

          make_request
        end

        it "returns a 410 Not found" do
          assert_equal 410, last_response.status
        end

        it "returns an empty JSON body" do
          make_request
          last_response.body.must_equal("{}")
        end
      end

      describe "because GitHub is not reachable" do
        before do
          @fake_github_service.expects(:remove_github_deploy_key).
              with(repo_name: "github-service-#{@instance_id}", deploy_key_title: @binding_id).
              raises GithubServiceHelper::GithubUnreachableError
          make_request
        end

        it "returns 504 Gateway Timeout" do
          assert_equal 504, last_response.status
        end

        it "returns a JSON response explaining the error" do
          expected_json = {
              "description" => "GitHub is not reachable"
          }.to_json

          assert_equal expected_json, last_response.body
        end
      end

      describe "because GitHub returns any other error" do
        before do
          @fake_github_service.expects(:remove_github_deploy_key).
              with(repo_name: "github-service-#{@instance_id}", deploy_key_title: @binding_id).
              raises GithubServiceHelper::GithubError.new("some message")
          make_request
        end

        it "returns 502 Bad Gateway" do
          assert_equal 502, last_response.status
        end

        it "returns a JSON response explaining the error" do
          expected_json = {
              "description" => "some message"
          }.to_json

          assert_equal expected_json, last_response.body
        end
      end
    end
  end
end

describe "delete /v2/service_instances/:instance_id" do
  before do
    @instance_id = "1234-5678"
  end

  def make_request
    delete "/v2/service_instances/#{@instance_id}"
  end

  describe "when basic auth credentials are missing" do
    before do
      make_request
    end

    it "returns a 401 unauthorized response" do
      assert_equal 401, last_response.status
    end
  end

  describe "when basic auth credentials are incorrect" do
    before do
      authorize "admin", "wrong-password"
      make_request
    end

    it "returns a 401 unauthorized response" do
      assert_equal 401, last_response.status
    end
  end

  describe "when basic auth credentials are correct" do
    before do
      authorize "admin", "password"

      @fake_github_service = mock
      GithubServiceHelper.stubs(:new).returns(@fake_github_service)
    end

    describe "when repo is successfully deleted" do
      before do
        @fake_github_service.stubs(:delete_github_repo).with("github-service-#{@instance_id}").
            returns(true)
        make_request
      end

      it "returns '200 OK'" do
        assert_equal 200, last_response.status
      end

      it "specifies the content type of the response" do
        last_response.header["Content-Type"].must_include("application/json")
      end

      it "returns empty JSON" do
        assert_equal "{}", last_response.body
      end
    end

    describe "when repo deletion fails" do
      describe "because the specified repo is not found" do
        before do
          @fake_github_service.stubs(:delete_github_repo).with("github-service-#{@instance_id}").
              returns(false)
          make_request
        end

        it "returns a 410 Not found" do
          assert_equal 410, last_response.status
        end

        it "returns an empty JSON body" do
          last_response.body.must_equal("{}")
        end
      end

      describe "because GitHub is not reachable" do
        before do
          @fake_github_service.stubs(:delete_github_repo).with("github-service-#{@instance_id}").
              raises GithubServiceHelper::GithubUnreachableError
          make_request
        end

        it "returns 504 Gateway Timeout" do
          assert_equal 504, last_response.status
        end

        it "returns a JSON response explaining the error" do
          expected_json = {
              "description" => "GitHub is not reachable"
          }.to_json

          assert_equal expected_json, last_response.body
        end
      end

      describe "because GitHub returns any other error" do
        before do
          @fake_github_service.stubs(:delete_github_repo).with("github-service-#{@instance_id}").
              raises GithubServiceHelper::GithubError.new("some message")
          make_request
        end

        it "returns 502 Bad Gateway" do
          assert_equal 502, last_response.status
        end

        it "returns a JSON response explaining the error" do
          expected_json = {
              "description" => "some message"
          }.to_json

          assert_equal expected_json, last_response.body
        end
      end
    end
  end
end
