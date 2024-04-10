/*globals angular, unused, navigator, _, document */
angular.module('workships-mobile').controller('desktopClientController', ['$scope', 'ajaxService', 'mobileAppService', '$timeout' ,function ($scope, ajaxService, mobileAppService) {
  'use strict';

  var WIDTH = 640;
  var CIRCLE_WIDTH = 40;

  function setView(status) {
    switch (status) {
    case 'first time':
      mobileAppService.setFirstEnterView();
      break;
    case 'done':
      mobileAppService.setFinishView();
      break;
    case 'in process':
      mobileAppService.setWelcomeBackView();
      break;
    default:
      mobileAppService.setWelcomeBackView();
    }
  }

  function initFromParams(data) {
    mobileAppService.setIndexOfCurrentQuestion(data.current_question_position);
    mobileAppService.setTotalQuestions(data.total_questions);
    mobileAppService.setDirection(data.language)
    if (data.min === data.max) {
      mobileAppService.setQuestionTypeClearScreen();
    } else {
      mobileAppService.setQuestionTypeMinMax(data.min, data.max);
    }
    setView(data.status);
  }

  $scope.getNumber = function (num) {
    return new Array(num);
  };

  $scope.detectMobile = function () {
    var mobileDetectRegex = /Mobile|iP(hone|od|ad)|Android|BlackBerry|IEMobile|Kindle|NetFront|Silk-Accelerated|(hpw|web)OS|Fennec|Minimo|Opera M(obi|ini)|Blazer|Dolfin|Dolphin|Skyfire|Zune/;
    return mobileDetectRegex.test(navigator.userAgent);
  };

  function createTopBar(total_questions) {
    $scope.dot_list = (WIDTH - (total_questions * CIRCLE_WIDTH)) / (total_questions - 1);
    $scope.dot_list = parseInt($scope.dot_list / 6.2);
    $scope.dot_list = new Array($scope.dot_list);
  }

  $scope.display_search = function() {
    if($scope.is_contain_funnel_question && !$scope.is_funnel_question)
      return false;
    return true;
  };

  $scope.clearSearch = function () {
    $scope.search_input.text = '';
  };

  $scope.getEmployee = function (id) {
    return (_.find($scope.workers, { id: id }));
  };

  function getSearchList() {
    return function () {
      var res = [];
      _.each($scope.workers, function (emp) {
        if (!emp) { return; }
        if (_.find($scope.replies, { employee_details_id: emp.id, selected: true })) { return; }
        var role = emp.role === undefined ? 'N/A' : emp.role;
        res.push({
          id: emp.id,
          name: emp.name + ', ' + role,
        });
      });
      return res;
    };
  }

  $scope.onSelectEmployee = function ($item) {
    var employee_with_focus =  _.find($scope.r.responses, { 'employee_details_id': $item.id });
    $scope.currentlyFocusedEmployeeId = employee_with_focus.employee_id;
  };

  function updateReplies() {
    var x;
    _.each($scope.selected_workers, function (value) {
      x = _.find($scope.replies, { employee_details_id: value});
      x.answer = true;
    });
    _.each($scope.unselected_workers, function (value) {
      x = _.find($scope.replies, { employee_details_id: value});
      x.answer = false;
    });
  }

  $scope.scrollTo = function (worker_id) {
    var worker_index = $scope.getWorkerIndexInRepliesArray(worker_id);
    var workers = document.getElementsByClassName("emp");
    var chosen_worker_offset = workers.item(worker_index).offsetTop;
    document.getElementById('select-workers-section').scrollTop = chosen_worker_offset - 50;
  };

  function handleGetNextQuestionReply(response, continue_questionnair) {
    if (response.data.status === 'done') {
      mobileAppService.setFinishView();
    }
    $scope.is_contain_funnel_question = response.data.is_contain_funnel_question
    $scope.is_funnel_question = response.data.is_funnel_question
    $scope.is_snowball_q = response.data.is_snowball_q;
    $scope.selected_workers = []
    $scope.replies = response.data.replies;
    $scope.response = response;
    $scope.question_title = response.data.question_title;
    $scope.response.q_id = response.data.q_id;
    $scope.current_emp_id = response.data.current_emp_id;
    $scope.question_number = response.data.current_question_position;
    $scope.total_questions = response.data.total_questions;
    $scope.question = response.data.question;
    $scope.minimum_required = response.data.client_min_replies || 1;
    $scope.maximum_required = response.data.client_max_replies;
    $scope.dependent_maximum_required = response.data.client_min_replies;
    $scope.dependent_minimum_required = response.data.client_max_replies;
    $scope.external_id = response.data.external_id;
    $scope.referral_btn_url = response.data.referral_btn_url
    $scope.referral_btn_text = response.data.referral_btn_text
    $scope.close_title = response.data.close_title
    $scope.close_sub_title = response.data.close_sub_title
    $scope.is_referral_btn = response.data.is_referral_btn
    createTopBar($scope.total_questions);
    $scope.getGroups();
    if (continue_questionnair === undefined) {
      initFromParams(response.data);
    }

    $scope.is_dependent = response.data.is_dependent;
    console.log($scope.replies)
    $scope.dependent_selected_worker = $scope.replies[0].employee_details_id;
    $scope.reset_messages = false;
  }

  $scope.sendAnswers = function() {
    var chosen_workers_size = $scope.selected_workers.length;
    if (chosen_workers_size < $scope.minimum_required) {
      $scope.selected_less_then_minimum = true;
      return false;
    }
    $scope.selected_less_then_minimum = false;

    $scope.response.replies = $scope.replies;
    var params = {
      token: $scope.token,
      replies: $scope.response.replies,
      desktop: 'true'
    };
    $scope.selected_workers = []
    // Close the question, then get the next question, and finally check
    //   if we're done.
    ajaxService.close_question(params).then(function () {
      ajaxService.get_next_question(params).then(function(response) {
        handleGetNextQuestionReply(response, true);
        if (response.data.status === 'done') {
          setView(response.data.status);
        }
      });
    });
  };

  $scope.sendDependentAnswers = function() {
    $scope.reset_messages = false;
    if ($scope.continue_next === false) {
      return true;
    }
    $scope.continue_next = false;
    var selected = $scope.approved_or_disapproved_workers.length;
    if (selected < $scope.dependent_minimum_required) {
      $scope.selected_less_then_minimum = true;
    } else {
      $scope.selected_less_then_minimum = false;
    }
    if ((($scope.dependent_maximum_required < selected)) || ($scope.dependent_minimum_required > selected)) {
      $scope.continue_next = true;
      return false;
    }
    updateReplies();
    $scope.response.replies = $scope.replies;
    ajaxService.get_next_question($scope.response).then(function () {
      handleGetNextQuestionReply($scope.response, true);
    });
  };

  function createEmployeeReply(employee_id) {
    $scope.replies.push({
      answer: null,
      e_id: null,
      employee_details_id: employee_id,
    });
    return _.last($scope.replies);
  }

  // start of "Add unverified employee" part

  $scope.userExists = true;
  $scope.showModal = false;

  $scope.departments = [{id: 1, name: 'Department1'}, {id: 2, name: 'Department2'}] // For now it's manual values

  $scope.employee = {
    firstname: '',
    lastname: '',
    department: ''
  };

  $scope.clearEmployeeObject = function () {
    $scope.employee.firstname = '';
    $scope.employee.lastname = '';
    $scope.employee.department = '';
  }

  $scope.checkIfUserExists = function(inputText) {
    //console.log($scope.userExists);
    const lowerCaseInputText = inputText.toLowerCase();

    $scope.userExists = $scope.search_list().some(user =>
        user.name.toLowerCase().includes(lowerCaseInputText)
    );
    console.log($scope.userExists);
    //return $scope.userExists
  };

  $scope.splitOrAddSearchResultToForm = function () {
    if ($scope.search_input.text && $scope.search_input.text.trim() !== '') {
      if ($scope.search_input.text.includes(' ')) {
        var wordsArray = $scope.search_input.text.split(' ');
        $scope.employee.firstname = wordsArray[0]
        $scope.employee.lastname = wordsArray[1]
      } else {
        $scope.employee.firstname = $scope.search_input.text;
      }
    }
  }

  $scope.showModalForAddUnverifiedEmployee = function() {
    console.log($scope)
    $scope.userExists = !$scope.userExists
    $scope.splitOrAddSearchResultToForm()
    $scope.search_input.text = ''
    $scope.showModal = !$scope.showModal;
  };

  $scope.closeModalFunc = function() {
    $scope.showModal = !$scope.showModal;
  };

  $scope.submitUnverifiedEmployeeForm = function() {
    var data = {
      e_first_name: $scope.employee.firstname,
      e_last_name: $scope.employee.lastname,
      e_group: $scope.employee.department,
      qpid : $scope.response.data.qpid,
      token : $scope.token
    };

    ajaxService.createUnverifiedEmployee(data).then(function(response) {
      console.log("Response:", response.data);
      // For some reason question_id is undefined;
      var newUserResponse = {
        employee_details_id: response.data.e_id,
        employee_id: response.data.qpid,
        response: null
      }; //
      var newEmployeeObject = {
        id: response.data.e_id,
        name: response.data.name,
        qp_id: response.data.qpid,
        role: "Employee",
        image_url: response.data.image_url
      } // workers
      var newUserDataRepliesResponse = {
        e_id: response.data.qpid,
        employee_details_id: response.data.e_id,
        answer: true,
        selected: true
      }; // replies
      // Here we modify all arrays and objects for display new employee
      $scope.workers.push(newEmployeeObject)
      //$scope.tiny_array.push(newUserResponse)
      //$scope.responses.undefined.responses.push(newUserResponse);
      $scope.replies.push(newUserDataRepliesResponse)
      $scope.selected_workers.push(response.data.e_id)
      $scope.numOfReplies();
      //$scope.currentlyFocusedEmployeeId = $scope.nextEmployeeIdWithoutResponseForQuestion(undefined, response.data.qpid);
      $scope.clearEmployeeObject();
      $scope.closeModalFunc()
      console.log($scope)
    }).catch(function(error) {
      console.error("Error:", error);
    });
  };

  $scope.getGroups = function () {
    console.log($scope.response.data.qpid)
    var param = {qid : $scope.response.data.qpid, token: mobileAppService.getToken()}
    ajaxService.getGroups(param).then(function(response) {
      console.log(response.data.groups)
      $scope.departments = response.data.groups;
    })
  }

  // end of "Add unverified employee" part

  $scope.numOfReplies = function() {
    return  _.filter($scope.replies, function(r) {
      return r.answer !== null;
    }).length;
  };

  function findOrCreateEmployeeIdInEmployeeReplies(employee_id) {
    var employee_replies =  _.find($scope.replies, { employee_details_id: employee_id});
    if (!employee_replies) { employee_replies = createEmployeeReply(employee_id); }
    return employee_replies;
  }

  $scope.select_worker = function (worker, selected) {
    var employee_replies = findOrCreateEmployeeIdInEmployeeReplies(worker.id);
    var i = $scope.selected_workers.indexOf(employee_replies.employee_details_id);
    if (i !== -1 && selected === true) { return; }
    if (i === -1) {
      if ($scope.maximum_required <= $scope.selected_workers.length) {
        return false;
      }
      $scope.selected_workers.push(employee_replies.employee_details_id);
      $scope.selected_maximum += 1;
    } else {
      $scope.selected_maximum -= 1;
      $scope.selected_workers.splice(i, 1);
    }
    if (selected) {
      employee_replies.selected = selected;
      employee_replies.answer = selected;
      if (selected === true) { $scope.clearSearch(); }
    } else {
      employee_replies.selected = !employee_replies.selected;
      employee_replies.answer = !employee_replies.answer;
    }

    // Also update $scope.replies
    if (selected === false) {
      var reply = _.find($scope.replies, function(r) { return r.e_id === employee_replies.e_id; });
      reply.answer = null;
    }
  };

  $scope.approve_worker = function (id) {
    var selected_id = $scope.selected_workers.indexOf(id);
    if (selected_id === -1) {
      $scope.selected_workers.push(id);
      $scope.selected_maximum += 1;
    }
    var unselected_id = $scope.unselected_workers.indexOf(id);
    if (unselected_id !== -1) {
      $scope.unselected_workers.splice(unselected_id, 1);
    }
    $scope.approved_or_disapproved_workers = $scope.selected_workers.concat($scope.unselected_workers);
  };

  $scope.disapprove_worker = function (id) {
    var selected_id = $scope.selected_workers.indexOf(id);
    if (selected_id !== -1) {
      $scope.selected_maximum -= 1;
      $scope.selected_workers.splice(selected_id, 1);
    }
    var unselected_id = $scope.unselected_workers.indexOf(id);
    if (unselected_id === -1) {
      $scope.unselected_workers.push(id);
    }
    $scope.approved_or_disapproved_workers = $scope.selected_workers.concat($scope.unselected_workers);
  };

  $scope.continueAnsweringFlow = function () {
    $scope.moveToNextWorker();
    $scope.scrollTo($scope.getSelectedWorker());
    $scope.reset_messages = true;
  };

  $scope.select_dependent_worker = function (id) {

    $scope.dependent_selected_worker = id;
  };

  Array.prototype.getIndexBy = function (name, value) {
    var i;
    for (i = 0; i < this.length; i++) {
      if (this[i][name] === value) {
        return i;
      }
    }
    return -1;
  };

  $scope.getWorkerIndexInRepliesArray = function (id) {
    return $scope.replies.getIndexBy("employee_details_id", id);
  };

  $scope.moveToNextWorker = function () {
    if ($scope.getWorkerIndexInRepliesArray($scope.getSelectedWorker()) + 1 < $scope.replies.length) {
      $scope.select_dependent_worker($scope.replies[$scope.getWorkerIndexInRepliesArray($scope.getSelectedWorker()) + 1].employee_details_id);
    } else {
      $scope.select_dependent_worker($scope.replies[0].employee_details_id);
    }
  };

  $scope.getSelectedWorker = function () {
    return $scope.dependent_selected_worker;
  };

  $scope.isSelectedWorker = function (id) {
    return $scope.dependent_selected_worker === id;
  };

  $scope.clearDependentSelection = function () {
    $scope.selected_workers = [];
    $scope.unselected_workers = [];
    $scope.approved_or_disapproved_workers = [];
    $scope.reset_messages = true;
  };

  $scope.clearSelection = function () {
    $scope.selected_workers = [];
    _.forEach($scope.replies, function (worker) {
      worker.selected = false;
      worker.answer = null;
    });
  };

  $scope.isChecked = function (id) {
    return $scope.selected_workers.indexOf(id) !== -1;
  };

  $scope.isUnSelected = function (id) {
    return $scope.unselected_workers.indexOf(id) !== -1;
  };

  $scope.criteriaMatch = function (search, worker) {
    var emp_list = [];
    _.each($scope.workers, function (w) { if (_.include(w.name.toLocaleLowerCase(), search.toLocaleLowerCase())) { emp_list.push(w.id); } });
    return (_.include(emp_list, worker.e_id));
  };

  $scope.matchString = function (pattern, str) {
    if (pattern === undefined || pattern === null || pattern === "") { return true; }
    return (str.toLowerCase().indexOf(pattern.toLowerCase()) >= 0);
  };

  $scope.continue = function () {
    var chosen_workers_size = $scope.selected_workers.length;
    if (chosen_workers_size < $scope.minimum_required) {
      $scope.selected_less_then_minimum = true;
    } else {
      $scope.selected_less_then_minimum = false;
    }
  };

  $scope.getInclude = function () {
    if ($scope.is_dependent === true) {
      return "desktop_dependent";
    }
    return "desktop";
  };

  $scope.answeredAllQuestions = function () {
    return $scope.approved_or_disapproved_workers.length === $scope.dependent_minimum_required;
  };
  $scope.referralUrl = function () {
    var ref_url = '';
    if($scope.referral_btn_url)
      ref_url = $scope.referral_btn_url + String($scope.external_id);
    return ref_url;
  };

  $scope.referralBtnText = function (defualt_text) {
    if($scope.referral_btn_text)
      return $scope.referral_btn_text;
    else
      return defualt_text;
  }

  $scope.closeTitle = function (defualt_text) {
    if($scope.close_title)
      return $scope.close_title;
    else
      return defualt_text;
  }
  $scope.closeSubTitle = function (defualt_text) {
    if($scope.close_sub_title)
      return $scope.close_sub_title;
    else
      return defualt_text;
  }

  $scope.init = function (name, token, dict) {
    $scope.token = token;
    $scope.name = name;

    $scope.names = {};
    $scope.worker_names = {};
    $scope.continue_next = true;
    $scope.selected_less_then_minimum = false;
    $scope.search_input = { text: ''};
    $scope.workers = null;
    $scope.selected_workers = [];
    $scope.unselected_workers = [];
    $scope.approved_or_disapproved_workers = $scope.selected_workers.concat($scope.unselected_workers);
    $scope.mobile_app_service = mobileAppService;
    $scope.allowed_clicking = $scope.maximum_required > $scope.selected_workers.length;
    mobileAppService.setToken(token);
    mobileAppService.setUserName(name);
    mobileAppService.setDictionary(dict)
    var params = { token: token,
                   desktop: 'true' };
    ajaxService.get_employees(params).then(function (response) {
      console.log(response.data)
      $scope.workers = response.data;
      $scope.search_list = getSearchList();
      _.forEach($scope.workers, function (worker) { $scope.names[worker.id] = worker.name + ', ' + worker.role; });
    });

    ajaxService.keepAlive({alive: true});

    ajaxService.get_next_question(params).then(function (response) {
      handleGetNextQuestionReply(response);
    });
  };
}]);
