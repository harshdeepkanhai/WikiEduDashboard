# frozen_string_literal: true

require 'rails_helper'

describe 'Student users', type: :feature, js: true do
  before do
    include type: :feature
    include Devise::TestHelpers
    page.current_window.resize_to(1920, 1080)
  end

  let(:user) { create(:user, wiki_token: 'foo', wiki_secret: 'bar') }
  let!(:instructor) { create(:user, username: 'Professor Sage') }
  let!(:classmate) { create(:user, username: 'Classmate') }
  let!(:campaign) { create(:campaign) }
  let!(:course) do
    create(:course,
           title: 'An Example Course',
           school: 'University',
           term: 'Term',
           slug: 'University/An_Example_Course_(Term)',
           submitted: true,
           passcode: 'passcode',
           start: '2015-01-01'.to_date,
           end: '2020-01-01'.to_date)
  end
  let!(:editathon) do
    create(:editathon,
           title: 'An Example Editathon',
           school: 'University',
           term: 'Term',
           slug: 'University/An_Example_Editathon_(Term)',
           submitted: true,
           passcode: '',
           start: '2015-01-01'.to_date,
           end: '2020-01-01'.to_date)
  end

  before do
    create(:courses_user,
           user: instructor,
           course: course,
           role: CoursesUsers::Roles::INSTRUCTOR_ROLE)
    create(:campaigns_course,
           campaign: campaign,
           course: course)
    create(:campaigns_course,
           campaign: campaign,
           course: editathon)
    create(:courses_user,
           user: classmate,
           course: course,
           role: CoursesUsers::Roles::STUDENT_ROLE)
    stub_add_user_to_channel_success
  end

  after do
    logout
  end

  describe 'clicking log out' do
    it 'logs them out' do
      login_as(user, scope: :user)

      visit "/courses/#{Course.first.slug}"
      expect(page).to have_content 'Log out'
      expect(page).not_to have_content 'Log in'
      click_link 'Log out'
      expect(page).to have_content 'Log in'
      expect(page).not_to have_content 'Log out'
    end

    it 'does not cause problems if done twice' do
      login_as(user, scope: :user)

      visit "/courses/#{Course.first.slug}"
      click_link 'Log out'
      visit '/sign_out'
    end
  end

  describe 'enrolling and unenrolling by button' do
    it 'joins and leaves a course' do
      login_as(user, scope: :user)
      stub_oauth_edit

      # click enroll button, enter passcode in alert popup to enroll
      visit "/courses/#{Course.first.slug}"

      expect(page).to have_content 'An Example Course'

      click_button 'Join course'
      within('.confirm-modal') do
        find('input').set('passcode')
        click_button 'OK'
      end

      sleep 3

      visit "/courses/#{Course.first.slug}/students"
      expect(find('tbody', match: :first)).to have_content User.last.username

      # now unenroll
      visit "/courses/#{Course.first.slug}"

      expect(page).to have_content 'An Example Course'

      click_button 'Leave course'
      within('.confirm-modal') do
        click_button 'OK'
      end

      sleep 3

      visit "/courses/#{Course.first.slug}/students"
      expect(find('tbody', match: :first)).not_to have_content User.last.username
    end

    it 'redirects to an error page if passcode is incorrect, with retry option' do
      login_as(user, scope: :user)
      visit "/courses/#{course.slug}"
      click_button 'Join course'
      within('.confirm-modal') do
        find('input').set('wrong_passcode')
        click_button 'OK'
      end
      expect(page).to have_content 'Incorrect passcode'
      within '.section-header' do
        find('input').set('passcode')
        click_button 'Enroll'
      end
      stub_oauth_edit
      click_link 'Join'
      expect(page).to have_content 'successfully joined'
      click_link 'Students'
      expect(find('tbody', match: :first)).to have_content user.username
    end

    it 'joins an Editathon without a passcode' do
      login_as(user, scope: :user)
      stub_oauth_edit

      # click enroll button, enter passcode in alert popup to enroll
      visit "/courses/#{editathon.slug}"

      expect(page).to have_content 'An Example Editathon'

      click_button 'Join program'
      within('.confirm-modal') do
        click_button 'OK'
      end

      sleep 3

      visit "/courses/#{editathon.slug}/students"
      expect(find('tbody', match: :first)).to have_content User.last.username
    end
  end

  describe 'visiting the ?enroll=passcode url' do
    it 'joins a course' do
      login_as(user, scope: :user)
      stub_oauth_edit

      visit "/courses/#{Course.first.slug}?enroll=passcode"
      expect(page).to have_content User.last.username
      click_link 'Join'
      expect(page).to have_content 'My Articles'
      click_link 'Students'
      expect(find('tbody', match: :first)).to have_content User.last.username
      # Now try enrolling again, which shouldn't cause any errors
      visit "/courses/#{Course.first.slug}/enroll/passcode"
    end

    it 'works even if a student is not logged in' do
      login_as(user, scope: :user)
      logout
      OmniAuth.config.test_mode = true
      allow_any_instance_of(OmniAuth::Strategies::Mediawiki)
        .to receive(:callback_url).and_return('/users/auth/mediawiki/callback')
      OmniAuth.config.mock_auth[:mediawiki] = OmniAuth::AuthHash.new(
        provider: 'mediawiki',
        uid: '12345',
        info: { name: 'Ragesock' },
        credentials: { token: 'foo', secret: 'bar' }
      )
      stub_oauth_edit
      logout
      visit "/courses/#{Course.first.slug}?enroll=passcode"
      find(:link, 'Log in with Wikipedia', match: :first).click
      expect(page).to have_content 'Ragesock'
      # User should be automatically redirected to the enroll link
      # upon login.
      click_link 'Students'
      expect(find('tbody', match: :first)).to have_content 'Ragesock'
    end

    it 'works even if a student has never logged in before' do
      stub_list_users_query_with_no_email # handles the check for wiki email

      OmniAuth.config.test_mode = true
      allow_any_instance_of(OmniAuth::Strategies::Mediawiki)
        .to receive(:callback_url).and_return('/users/auth/mediawiki/callback')
      OmniAuth.config.mock_auth[:mediawiki] = OmniAuth::AuthHash.new(
        provider: 'mediawiki',
        uid: '123456',
        info: { name: 'Ragesoss' },
        credentials: { token: 'foo', secret: 'bar' }
      )
      allow_any_instance_of(WikiApi).to receive(:get_user_id).and_return(234567)
      stub_oauth_edit
      logout
      visit "/courses/#{Course.first.slug}?enroll=passcode"
      find(:link, 'Log in with Wikipedia', match: :first).click
      expect(find('.intro')).to have_content 'Ragesoss'
      click_link 'Start'
      fill_in 'name', with: 'Sage Ross'
      fill_in 'email', with: 'sage@example.com'
      click_button 'Submit'
      click_link 'Finish'
      # User should be redirected to enroll URL upon completion of
      # onboarding form.
      click_link 'Students'
      expect(find('tbody', match: :first)).to have_content 'Ragesoss'
    end

    it 'does not work if user is not persisted' do
      OmniAuth.config.test_mode = true
      allow_any_instance_of(OmniAuth::Strategies::Mediawiki)
        .to receive(:callback_url).and_return('/users/auth/mediawiki/callback')
      OmniAuth.config.mock_auth[:mediawiki] = OmniAuth::AuthHash.new(
        provider: 'mediawiki',
        uid: '123456',
        info: { name: 'Ragesoss' },
        credentials: { token: 'foo', secret: 'bar' }
      )
      allow(UserImporter).to receive(:from_omniauth).and_return(build(:user, id: 2345678))
      stub_oauth_edit
      logout
      visit "/courses/#{Course.first.slug}/enroll/passcode"
      visit "/courses/#{Course.first.slug}/students"
      sleep 1
      expect(first('tbody')).not_to have_content 'Ragesoss'
    end

    it 'redirects to a login error page if login fails' do
      logout
      OmniAuth.config.test_mode = true
      allow_any_instance_of(OmniAuth::Strategies::Mediawiki)
        .to receive(:callback_url).and_return('/users/auth/mediawiki/callback')
      OmniAuth.config.mock_auth[:mediawiki] = OmniAuth::AuthHash.new(
        extra: { raw_info: { login_failed: true } }
      )
      visit "/courses/#{Course.first.slug}/enroll/passcode"
      expect(page).to have_content 'Login Error'
    end
  end

  describe 'inputing an assigned article' do
    it 'assigns the article' do
      login_as(user, scope: :user)
      stub_raw_action
      stub_oauth_edit
      stub_info_query
      create(:courses_user,
             course: course,
             user: user,
             role: CoursesUsers::Roles::STUDENT_ROLE)
      visit "/courses/#{Course.first.slug}/students"
      # Add an assigned article
      click_button 'Assign myself an article'
      within('#users') { find('input', match: :first).set('Selfie') }
      click_button 'Assign'
      click_button 'OK'
      click_button 'Done'
      expect(page.all('tr.students')[1]).to have_content 'Selfie'
      expect(find('tr.students', match: :first)).not_to have_content 'Selfie'
    end
  end

  describe 'inputing a reviewed article' do
    it 'assigns the review' do
      login_as(user, scope: :user)
      stub_raw_action
      stub_oauth_edit
      stub_info_query
      create(:courses_user,
             course: course,
             user: user,
             role: CoursesUsers::Roles::STUDENT_ROLE)
      visit "/courses/#{Course.first.slug}/students"
      click_button 'Review an article'
      within('#users') { find('input', match: :first).set('Self-portrait') }
      click_button 'Assign'
      click_button 'OK'
      click_button 'Done'
      expect(page).to have_content 'Self-portrait'
    end
  end

  describe 'clicking remove for an assigned article' do
    it 'removes the assignment' do
      login_as(user, scope: :user)
      stub_raw_action
      stub_oauth_edit
      stub_info_query
      create(:courses_user,
             course: course,
             user: user,
             role: CoursesUsers::Roles::STUDENT_ROLE)
      create(:assignment,
             article_title: 'Selfie',
             course: course,
             user: user,
             article_id: nil,
             role: Assignment::Roles::ASSIGNED_ROLE)
      visit "/courses/#{Course.first.slug}/students"
      # Remove the assignment
      click_button '+/-'
      accept_confirm do
        click_button '-'
      end
      sleep 0.5
      visit "/courses/#{Course.first.slug}/students"
      sleep 1
      expect(page).not_to have_content 'Selfie'
    end
  end

  describe 'visiting the dashboard homepage' do
    it 'sees their course' do
      login_as(user, scope: :user)

      create(:courses_user,
             course: course,
             user: user,
             role: CoursesUsers::Roles::STUDENT_ROLE)

      visit root_path
      expect(page).to have_content 'My Dashboard'
      expect(page).to have_content 'An Example Course'
    end
  end
end
