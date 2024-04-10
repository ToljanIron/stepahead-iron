/*globals angular, unused, localStorage, _, $, document, Promise */
'use strict';

angular.module('workships-mobile')
  .config(['$logProvider', function($logProvider){
        $logProvider.debugEnabled(false);
  }])
  .controller('mobileQuestionnaireController', [
    '$scope', 'ajaxService', '$q', 'mobileAppService', '$timeout', '$log','$window', '$document', '$interval','localStorageService',
    function ($scope, ajaxService, $q, mobileAppService, $timeout, $log, $window, $document, $interval, $localStorageService) {

  var undo_stack = [];
  var mass = mobileAppService.s;

  function buildQuestionResponseStructs() {
    $scope.responses = {};

    var q = $scope.questions_to_answer;
    console.log(q)
    $scope.responses[q.id] = {
      question_id: q.id,
      question: q.question,
      question_title: q.question_title,
      question_first_line: q.question_first_line,
      is_selection_question: q.is_selection_question,
      selection_question_options: q.selection_question_options,

      responses: _.map(q.employee_data, function (data) {
        return {
          employee_details_id: data.employee_details_id,
          employee_id: data.e_id,
          response: data.answer,
        };
      }),
    };
  }

  function getSearchList() {
    $log.debug('In getSearchList()');
    return function () {
      var res = [];
      _.each($scope.employees, function (emp) {
        if (!emp) { return; }
        if (_.find($scope.r.responses, { employee_details_id: emp.id, selected: true })) { return; }
        if ($scope.full_search || _.find($scope.r.responses, { employee_details_id: emp.id })) { 

       // if (!_.find($scope.tiny_array, {employee_details_id: emp.id}) ) {return;}
          var role = emp.role === undefined ? 'N/A' : emp.role;
          res.push({
            id: emp.id,
            name: emp.name, 
            role: role,
          });
        }
      });

      return res;
    };
  }

  function format_questions_to_answer(data) {
    console.log(data)
    $log.debug('In format_questions_to_answer()');
    var res = {};
    if (data.question !== null){
      var processedQuestion = processString(data.question);
      res.question_first_line = processedQuestion;
    }
    $log.debug('In format_questions_to_answer()');

    res.id = data.q_id;
    res.question = data.question;
    res.question_title = data.question_title;
    res.is_selection_question = data.is_selection_question;
    res.selection_question_options = data.selection_question_options;
    res.employee_data = [];
    _.each(data.replies, function (r) {
      if (r.answer === null) {
        res.employee_data.push({e_id: r.e_id, answer: r.answer, employee_details_id: r.employee_details_id});
      }
    });
    return res;
  }

  function processString(inputString) {
    const words = inputString.split(/\s+/);

    let result = '';
    let charCount = 0;
    const punctuationRegex = /[.,?!;:]+/g;

    for (const word of words) {
      const cleanedWord = word.replace(punctuationRegex, '');
      if ((charCount + cleanedWord.length) <= 37) {
        result += cleanedWord + ' ';
        charCount += cleanedWord.length + 1;
      } else {
        break;
      }
    }

    return result.trim();
  }

  $scope.clearSearch = function () {
    $scope.search_input.text = '';
    $scope.search_input.lastname = '';
    $scope.search_input.firstname = '';
  };

  $scope.responsesForQuestion = function (question_id) {
    $log.debug('In ponsesForQuestion()');
    var r = $scope.responses[question_id];
    if (!r) {
      return;
    }
    return r.responses;
  };

  $scope.responseForQuestionAndEmployee = function (question_id, employee_id) {
    $log.debug('In responseForQuestionAndEmployee()');
    var r = $scope.responsesForQuestion(question_id);
    var employee_response = _.where(r, {
      employee_id: employee_id
    });
    if (employee_response.length !== 1) {
      return;
    }
    if ($scope.is_snowball_q && employee_response.length !== 1) {
      console.log('here')
    }
    return employee_response[0];
  };

  $scope.nextEmployeeIdWithoutResponseForQuestion = function (question_id, employee_id) {
    $log.debug('In nextEmployeeIdWithoutResponseForQuestion()');
    var r = $scope.responsesForQuestion(question_id);
    var i, j;

    for (i = 0; i < r.length; ++i) {
      if (r[i].employee_id === employee_id) {
        for (j = i; j < r.length; ++j) {
          if (r[j].response === null) { return r[j].employee_id; }
        }
        for (j = i; j >= 0; --j) {
          if (r[j].response === null) { return r[j].employee_id; }
        }
      }
    }
    return -1;
  };

  function resetQuestion() {
    $scope.init(false, {reset_question: true});
  }

  function isLessAvailableEmployeesThanMinimum() {
    if (!mass.isFunnelQuestion()) { return; }

    if ($scope.numberOfEmployeesForQuestion($scope.r.question_id) - $scope.numberOfEmployeesAnsweredFalseForQuestion($scope.r.question_id) < mobileAppService.getMinMaxAmounts().min) {
      $timeout(function () {
        mobileAppService.displayOverlayBlocker(mobileAppService.getMinMaxAmounts().min, {unblock_on_click: true});
        $scope.onUndo();
      }, 0);
    }
  }

  $scope.onUserResponse = function (question_id, employee_id, response, employee_details_id, needToFocus) {
    console.log(question_id, employee_id, response, employee_details_id, needToFocus);
    $log.debug('In onUserResponse()');

    $scope.state_saved[0] = false;
    var r = $scope.responseForQuestionAndEmployee(question_id, employee_id);
    if (!r) { return; }
    var undo_step = {
      question_id: question_id,
      employee_details_id: employee_details_id,
      employee_id: employee_id,
      response: response,
    };
    undo_stack.push(undo_step);

    r.response = response;
    console.log(response)
    mass.updateRepliesNumberUp(response);

    var emp = $scope.unselected_workers.splice(_.findIndex($scope.unselected_workers, {id: employee_id}), 1);

    var inx = $scope.search_added_emps.indexOf(employee_id);
    $scope.search_added_emps.splice( inx, inx + 1);
    var added_employee = _.find($scope.employees, function (e) {
      return e.qp_id === employee_id;
    });
    if (!_.any($scope.original_data.replies, function (reply) { return reply.e_id === employee_id; })) {
      $scope.original_data.replies.splice(0, 0, { e_id: employee_id, employee_details_id: added_employee.id });
    }
    if (emp[0]) { $scope.undo_worker_stack.push(emp[0]); }
    if (needToFocus === undefined || needToFocus === true) {
      $scope.currentlyFocusedEmployeeId = $scope.nextEmployeeIdWithoutResponseForQuestion(question_id, employee_id);
    }else{
      if($scope.currentlyFocusedEmployeeId == employee_id){
        $scope.currentlyFocusedEmployeeId = $scope.nextEmployeeIdWithoutResponseForQuestion(question_id, employee_id);
      }

    }

    // force click on next when the max number of replies was reached
    if ($scope.numberOfEmployeesAnsweredForQuestion($scope.r.question_id) === $scope.numberOfEmployeesForQuestion($scope.r.question_id)) {

      if ($scope.current_question_position === $scope.original_data.total_questions){
        console.log('congratz you reach end of questionarry')
        $scope.clearScreenOnFinish();
      }

      $scope.clicked_on_next[0] = true; // force click on next
    }

    if (mobileAppService.isQuestionTypeMinMax()) {
      isLessAvailableEmployeesThanMinimum();
    }

    // Save partial results to the database
    if ( ($scope.numberOfEmployeesAnsweredForQuestion($scope.r.question_id) % 3) === 0) {
      $scope.continueLater();
    }
    var pos = ($scope.employees.map(function(e) { return e.qp_id; })).indexOf(employee_id);
    $scope.employees.splice( pos, 1);
  };

  $scope.onUndo = function () {
    if ($scope.isUndoDisabled()) { return; }
    $scope.state_saved[0] = false;
    if (!$scope.clicked_on_next[0]) {
      var undo_step = undo_stack.pop();
      if (!undo_step) {
        resetQuestion();
        return;
      }
      var r = $scope.responseForQuestionAndEmployee(undo_step.question_id, undo_step.employee_id);
      $scope.unselected_workers.push($scope.undo_worker_stack.pop());
      if (!r) { return; }
      r.response = null;
      $scope.currentlyFocusedEmployeeId = undo_step.employee_id;

      mass.updateRepliesNumberDown(undo_step.response);
    }
    $scope.clicked_on_next[0] = false;
  };

  $scope.numberOfEmployeesForQuestion = function (question_id) {
    if ($scope.isLoaded()) {
      var r = $scope.responsesForQuestion(question_id);
      if (!r) { return -1; }
      return r.length;
    }
  };

  $scope.numberOfEmployeesAnsweredForQuestion = function (question_id) {
    if ($scope.isLoaded()) {
      var responses = $scope.responsesForQuestion(question_id);
      return _.filter(responses, function (r) {
        return r.response !== null;
      }).length;
    }
  };

  $scope.numberOfEmployeesAnsweredTrueForQuestion = function (question_id) {
    if ($scope.isLoaded()) {
      var responses = $scope.responsesForQuestion(question_id);
      //console.log('Debaging numberOfEmployeesAnsweredTrueForQuestion, need to check if there isset response answer')
      if (mass.is_funnel_question && mass.is_snowball_q) {
        //console.log(mass)
        return mass.num_replies_true ;
      }

      return _.filter(responses, function (r) {
        return r.response === true;
      }).length;
    }
  };

  /************************************************
   * New state implemenations
   ************************************************/

  $scope.numOfAnswers = function() {
    if (mass.is_funnel_question) {
      return mass.num_replies_true;
    }
    return mass.num_replies_true + mass.num_replies_false;
  };

  $scope.clientMaxReplies = function() {
    return mass.client_max_replies;
  };

  // If is a funnel question then only replies whose value is 'true' count.
  // Otherwise, we count both 'true' and 'false'
  $scope.isFinished = function () {
    var finished = false;
  console.log(mass)
    if (mass.is_funnel_question) {
      finished = mass.num_replies_true === mass.client_max_replies;
    } else {
      var num_reps = mass.num_replies_true + mass.num_replies_false;
      finished = num_reps === mass.client_max_replies;
    }

    if (finished) {
      // $scope.container.style.visibility = 'hidden';
      $scope.container.showValue = false;
    }

    return finished;
  };

  $scope.canFinish = function () {
    console.log(mass.is_funnel_question)
    if (mass.is_funnel_question) {
      return mass.num_replies_true >= mass.client_min_replies &&
             mass.num_replies_true <= mass.client_max_replies;
    }
    if (mass.is_selection_question) {
      var hasTrueValue = mass.selection_question_options.some(function(option) {
        return option.value === true;
      });
      return hasTrueValue;
    }
    var num_reps = mass.num_replies_true + mass.num_replies_false;
    console.log(num_reps)
    // console.log('&&&&&&&&&&&&&&&&&&&&&&&')
    // console.log(mass)
    // console.log('num_reps: ', num_reps, ', mass.client_max_replies: ', mass.client_max_replies)
    // console.log('&&&&&&&&&&&&&&&&&&&&&&&')
    console.log(num_reps === mass.client_max_replies)
    return num_reps === mass.client_max_replies
  };

  $scope.isAnsweredAllNessecearyQuestions = function () {
    // console.log('Deprecated function');
  };

  /************************************************
   * End of new state implemenations
   ************************************************/


  $scope.numberOfEmployeesAnsweredFalseForQuestion = function (question_id) {
    if ($scope.isLoaded()) {
      var responses = $scope.responsesForQuestion(question_id);
      return _.filter(responses, function (r) {
        return r.response === false;
      }).length;
    }
  };

  $scope.numberOfQuestions = function () {
    return _.keys($scope.responses).length;
  };

  $scope.employeeById = function (employee_id)  { // sometimes it's not employee id it's employee_detail_id
    var e =  _.find($scope.employees, {
      id: employee_id
    });
    return e;
  };
  $scope.getEmployeeImg = function (employee_id) {
    var e = $scope.employeeById(employee_id)
    //console.log(e);
    if(e.image_url && !e.image_url.match(/missing_user/))
      return e.image_url;
    return false;
  }

  $scope.getCiricleColor = function (index){
    // var idx = $scope.current_avatar_color;
    // var my_color
    // $scope.current_avatar_color ++
    // if($scope.current_avatar_color ==6)
    //   $scope.current_avatar_color =0;
    // var my_color = (mobileAppService.get_avatar_colors()[idx])


var my_color;
// if(index==0) 
//    my_color = mobileAppService.get_avatar_colors()[0]
// else 
  if(index%6==0)
  my_color = mobileAppService.get_avatar_colors()[5]
else if(index%5 ==0)
    my_color= mobileAppService.get_avatar_colors()[4]
else if(index%4==0)
  my_color = mobileAppService.get_avatar_colors()[3]
else if(index%3==0)
  my_color = mobileAppService.get_avatar_colors()[2]
else if(index%2==0)
  my_color = mobileAppService.get_avatar_colors()[1]
else 
  my_color = mobileAppService.get_avatar_colors()[0]
   // return {'background-color': my_color};
    return {"background-color": my_color};
  }

  $scope.shortEmpName = function (employee_id){
    // console.log(employee_id)
    // console.log($scope.employees)
    var e = $scope.employeeById(employee_id)
    return $scope.shortName(e.name)
  }
  $scope.shortName = function(name){
    var s_n = name.split(" ");
    return s_n[0].charAt(0) + s_n[1].charAt(0) ;
  }

  $scope.onForwardQuestion = function () {
    $log.debug('In onForwardQuestion()');
    var i = $scope.index_of_current_question - 1;
    if (i >= $scope.numberOfQuestions()) {
      return;
    }
    $scope.index_of_current_question = $scope.index_of_current_question + 1;
    $scope.r = $scope.responses[_.keys($scope.responses)[$scope.index_of_current_question - 1]];
  };

  $scope.employeeHasResponseForQuestion = function (question_id, employee_id) {
    $log.debug('In employeeHasResponseForQuestion()');
    var r = $scope.responseForQuestionAndEmployee(question_id, employee_id);
    if (!r) {
      return false;
    }
    return r.response !== null;
  };


  $scope.isUndoDisabled = function () {
    if ($scope.isLoaded()) {
      return $scope.numberOfEmployeesAnsweredForQuestion($scope.r.question_id) === 0;
    }
  };

  $scope.isLoaded = function () {
    return $scope.loaded[0];
  };
  $scope.removeUser = function (){
    return;
  }

  $scope.employeeDoesNotHaveResponseForQuestion = function (question_id, employee_id) {
    return !$scope.employeeHasResponseForQuestion(question_id, employee_id);
  };

  $scope.searchAdded = function (employee_id) {
    return _.any($scope.search_added_emps, function (id) { return id === employee_id; });
  };

  $scope.displayMaxAmount = function () {
    $log.debug('In displayMaxAmount()');
    if (!$scope.isLoaded()) { return; }
    if ((mobileAppService.getMinMaxAmounts().max > $scope.numberOfEmployeesForQuestion($scope.r.question_id)) && !$scope.is_snowball_q_first_step) {
      return $scope.numberOfEmployeesForQuestion($scope.r.question_id);
    }
    if ($scope.is_snowball_q_first_step && $scope.is_snowball_q){
      return mass.max;
    }
    return mobileAppService.getMinMaxAmounts().max;
  };

  $scope.showOrHideQ = function(event) {
    var target = event.target;
    if (target.classList.contains('close-btn')) return
    if (!$scope.show_full_question && (target.classList.contains('question-container-display') || target.classList.contains('ng-scope'))) {
      $scope.show_popup = true;
      $scope.show_full_question = true;
      $scope.showValue = true;
    //$scope.show_full_question = !$scope.show_full_question;
    //$scope.show_popup = !$scope.show_popup;
    //$scope.showValue = !$scope.showValue;
    if ($scope.is_snowball_q_first_step){
      if ($scope.showModal) $scope.showModal = false
    }
    return
  }

    if (!target.classList.contains('v-idle-btn') && !target.classList.contains('v-idle-container') && !target.classList.contains('close-btn') && !target.classList.contains('close-q-container')) {
      if ($scope.show_full_question && (target.classList.contains('question-container-hide-display') || target.classList.contains('ng-scope'))) {
        //console.log($scope.show_full_question,$scope.show_popup,$scope.showValue)
        $scope.show_popup = false;
        $scope.show_full_question = false;
        $scope.showValue = false;
      }
      if ($scope.is_snowball_q_first_step){
        if (!$scope.showModal) $scope.showModal = true
      }
    }
  }

  $scope.toggleFullQuestionView = function () {
    $scope.show_full_question = !$scope.show_full_question;
    $scope.show_popup = !$scope.show_popup;
  };
  $scope.hidePopup = function (event) {
    var clickedElement = event.target;
    if (clickedElement)
    {
      var elementClasses = clickedElement.classList;
      var clickedOnPopup = (elementClasses.contains('genericPopUp') || (clickedElement.parentElement !== null && clickedElement.parentElement.classList.contains('genericPopUp')));
      if ($scope.is_snowball_q_first_step){
        $scope.showModal = !$scope.showModal
      }
      if (clickedOnPopup) return;
    }

    if($scope.show_full_question){
      $scope.show_popup = false;
      $scope.show_full_question = false;
      var height = $scope.container.offsetHeight;
      console.log($scope.show_popup,$scope.show_full_question);
      var translateYValue = getTranslateYValue(height);
      //$scope.container.style.transform = 'translateY(' + translateYValue + ')';
    }
    // else{
    //   $scope.show_popup = true;
    //   $scope.show_full_question = true;
    //   //container.style.transform = 'translateY(0%)';
    // }
  };

  function getTranslateYValue(height) {
    if (height > 900) return '15%';
    if (height > 800) return '15%';
    if (height > 600) return '15%';
    if (height > 380) return '15%';
    if (height > 320) return '15%';
    if (height > 260) return '15%';
  }

  // Back to first question snowball

  $scope.canShowBackToFirstQuestion = function () {
    // console.log('Debugging canShowBackToFirstQuestion')
    // console.log($scope)
    if (!$scope.is_snowball_q_first_step && $scope.can_return_to_first_q) return true;

    return false;
    //console.log($scope)
  }

  // Here we rewrite $scope and notify system that we on question_position 1

  $scope.rewriteScopeForFirstQ = function () {
    console.log('calling rewriteScopeForFirstQ')
    console.log('this is first q scope')
    console.log($scope.first_q)
    $scope.container.showValue = true;
    $scope.show_popup = true;
    $scope.show_full_question = true;
    console.log($scope.first_q)
    $scope.current_question_position = $scope.first_q.current_question_position;
    $scope.current_employee_id = $scope.first_q.current_employee_id;
    $scope.is_snowball_q = $scope.first_q.is_snowball_q;
    $scope.is_snowball_q_first_step = true;
    $scope.snowball_enable_autocomplete = $scope.first_q.snowball_enable_autocomplete;
    $scope.container = $document[0].querySelector('.question-container');
    $scope.questionnaire_id = $scope.first_q.questionnaire_id;
    $scope.q_state = $scope.first_q.q_state
    $scope.qp_state = $scope.first_q.qp_state
    $scope.status = $scope.first_q.status

    var oldReplies = $scope.original_data.replies;
    var oldEmployees = $scope.employees ;
    var oldTinyArray = $scope.tiny_array;
    var oldResponses = $scope.responses.undefined.responses;
    $scope.original_data = $scope.first_q;
    $scope.original_data.replies = oldReplies;
    $scope.replies = $scope.first_q.replies

    $scope.replies.forEach(item => {
      item.answer = true;
    });

    $scope.first_q.employees = oldEmployees;
    $scope.first_q.tiny_array = oldTinyArray;
    $scope.first_q.responses = $scope.first_q.responses || {};
    $scope.first_q.responses.undefined = $scope.first_q.responses.undefined || {};
    $scope.first_q.responses.undefined.responses = oldResponses;

    $scope.r.question_title = $scope.first_q.question_title;
    $scope.r.question = $scope.first_q.question
    $scope.r.is_selection_question = $scope.first_q.is_selection_question

    $scope.first_q.client_max_replies = $scope.first_q.max
    $scope.first_q.client_min_replies = $scope.first_q.answered;
    $scope.numberOfEmployeesForQuestion($scope.r.question_id);

    //$scope.container.style.transform = 'translateY(0%)';
    //$scope.toggleFullQuestionView()
    mobileAppService.setIndexOfCurrentQuestion($scope.first_q.current_question_position);

    if ($scope.first_q.min === $scope.first_q.max) {
      mobileAppService.setQuestionTypeClearScreen();
    } else {
      mobileAppService.setQuestionTypeMinMax($scope.first_q.min, $scope.first_q.max);
    }
    $scope.questions_to_answer = format_questions_to_answer($scope.first_q);
    $scope.r.question_first_line = $scope.questions_to_answer.question_first_line
    buildQuestionResponseStructs();
    $scope.responses.undefined.responses = oldResponses
    $scope.responses.undefined.responses.forEach(item => {
      item.response = true;
    });
    mobileAppService.updateState($scope.first_q);
    if($scope.first_q.is_contain_funnel_question && !$scope.first_q.is_funnel_question)
      $scope.full_search = false;
    console.log('scope after rewrite')
    console.log($scope);
  }

  $scope.returnToFirstQuestion = function () {

    if ($scope.current_question_position > 1){
      $scope.paramsForGettingFirstQ.q_num = 1;
      console.log('here is current position > 1')
      console.log($scope)
        ajaxService.getFirstQuestion($scope.paramsForGettingFirstQ).then( function (response) {
          $scope.first_q = response.data;
          canUserReturnToFirstQuestion($scope.first_q.answered,$scope.first_q.max);
          // before rewrite, we must cached our original data to manipulate it later
          $scope.cachedCurrentQ();
          $scope.rewriteScopeForFirstQ();
        })
    }

    // console.log('returning to first q')
    // if ($scope.first_q && $scope.first_q.current_question_position === 1){
    //   console.log($scope.first_q)
    //   console.log('im returning to q')
    //   $scope.rewriteScopeForFirstQ();
    // }
  }

  $scope.cachedCurrentQ = function () {
    var storageOriginalData = $localStorageService.getObject('original_data');
    var storageEmployees = $localStorageService.getObject('employees');
    var storageTinyArray = $localStorageService.getObject('tiny_array');
    var storageResponses = $localStorageService.getObject('responses');

    if (storageOriginalData) {
      $localStorageService.removeObject('original_data');
      $localStorageService.removeObject('employees');
      $localStorageService.removeObject('tiny_array');
      $localStorageService.removeObject('responses');
    }

    // we need to run this to prevent error if user is reloaded page of clear local storage
    if (storageEmployees == null){
      console.log('Handle get employee result cause empty storage')
      ajaxService.get_employees($scope.params).then( function (response) {
        handleEmployeesResult(response);
        $localStorageService.saveObject('employees', $scope.employees);
      })
    } else {
      $localStorageService.saveObject('employees', $scope.employees);
    }


    $localStorageService.saveObject('original_data', $scope.original_data);
    $localStorageService.saveObject('tiny_array', $scope.tiny_array);
    $localStorageService.saveObject('responses', $scope.responses.undefined.responses);
  }

  $scope.returnToCachedQ = function () {
    console.log('check difference beetween storageData and current mass' )
    var originalData = $localStorageService.getObject('original_data');
    console.log(originalData.current_question_position,mass.current_question_position)
    $scope.paramsForGettingFirstQ.q_num = mass.current_question_position;
    console.log('calling returnToCachedQ response')
    ajaxService.getFirstQuestion($scope.paramsForGettingFirstQ).then( function (response) {
      //$scope.first_q = response.data;
      $scope.rewriteCachedQ();
    })
  }

  $scope.rewriteCachedQ = function () {
    console.log('calling returnToCachedQ')
    var originalData = $localStorageService.getObject('original_data');
    console.log(originalData)
    $scope.showModal = false;
    $scope.r.question_title = originalData.question_title;
    $scope.r.question = originalData.question;
    $scope.r.is_selection_question = originalData.is_selection_question

    $scope.container.showValue = true;
    $scope.show_popup = true;
    $scope.show_full_question = true;

    $scope.current_question_position = originalData.current_question_position;
    $scope.current_employee_id = originalData.current_employee_id;
    $scope.is_snowball_q = originalData.is_snowball_q;
    $scope.is_snowball_q_first_step = false;
    $scope.snowball_enable_autocomplete = originalData.snowball_enable_autocomplete;
    $scope.container = $document[0].querySelector('.question-container');
    $scope.questionnaire_id = originalData.questionnaire_id;
    $scope.q_state = originalData.q_state
    $scope.qp_state = originalData.qp_state
    $scope.status = originalData.status

    var oldReplies = originalData.replies;
    var oldEmployees = $localStorageService.getObject('employees');
    var oldTinyArray = $localStorageService.getObject('tiny_array');
    var oldResponses = $localStorageService.getObject('responses');
    $scope.original_data = originalData;
    $scope.original_data.replies = oldReplies;
    $scope.replies = originalData.replies

    // $scope.replies.forEach(item => {
    //   item.answer = true;
    // });

    $scope.employees = oldEmployees;
    $scope.tiny_array = oldTinyArray;
    //$scope.responses = originalData.responses || {};
    //$scope.responses.undefined = oldResponses.responses.undefined || {};
    $scope.responses.undefined.responses = oldResponses;

    $scope.client_max_replies = originalData.client_max_replies
    $scope.client_min_replies = originalData.client_min_replies;
    $scope.numberOfEmployeesForQuestion($scope.r.question_id);
    $scope.currentlyFocusedEmployeeId = parseInt($scope.tiny_array[0].employee_id,10);
    console.log($scope.currentlyFocusedEmployeeId)

    //$scope.container.style.transform = 'translateY(0%)';
    //$scope.toggleFullQuestionView()
    mobileAppService.setIndexOfCurrentQuestion($scope.current_question_position);

    if ($scope.min === $scope.max) {
      mobileAppService.setQuestionTypeClearScreen();
    } else {
      mobileAppService.setQuestionTypeMinMax($scope.min, $scope.max);
    }
    $scope.questions_to_answer = format_questions_to_answer(originalData);
    $scope.r.question_first_line = $scope.questions_to_answer.question_first_line
    buildQuestionResponseStructs();
    //$scope.responses.undefined.responses = oldResponses
    // $scope.responses.undefined.responses.forEach(item => {
    //   item.response = true;
    // });
    mobileAppService.updateState($scope);
    if($scope.is_contain_funnel_question && !$scope.is_funnel_question)
      $scope.full_search = false;
    console.log('scope after rewrite when back to question')
    console.log($scope);
  }

  $scope.showPopup = function () {
    if (!$scope.show_full_question) {
      $scope.show_popup = true;
      $scope.show_full_question = true;
      if ($scope.is_snowball_q_first_step){
        $scope.showModal = !$scope.showModal
      }
      console.log('im here, maybe start page')
    }
  }

  $scope.logoSrc = function () {
    if(mass.logo_url)
      return mass.logo_url;
    else
      return '/assets/logo-medium.png';
  };
  $scope.newLogoSrc = function () {
      return '/assets/step_ahead_logo.png';
  };
  $scope.referralUrl = function () {
    var ref_url = '';
    if(mass.referral_btn_url)
      ref_url = mass.referral_btn_url + String(mass.external_id);
    return ref_url;
  };
  $scope.referralBtnColor = function () {
    var bg_color;
    if(mass.referral_btn_color)
      bg_color = mass.referral_btn_color;
    else
      bg_color = 'orange';
    return {"background-color": bg_color};
  };
  $scope.isReferralBtn = function(){
    return mass.is_referral_btn;
  }
  $scope.closeTitle = function () {
    var e = document.getElementById('close_title');
    var title = e.getAttribute('data-close-title');
    if(mass.close_title)
      return mass.close_title;
    else
      return title;
  };

  $scope.closeTextTitle1 = function (){
    var et1 = document.getElementById('close_text_title1');
    var text_title1 = et1.getAttribute('data-close-text-title1');
    if(mass.close_text_title1)
      return mass.close_text_title1;
    else
      return text_title1;
  };

  $scope.closeTextTitle2 = function (){
    var et2 = document.getElementById('close_text_title2');
    var text_title2 = et2.getAttribute('data-close-text-title2');
    if(mass.close_text_title2)
      return mass.close_text_title2;
    else
      return text_title2;
  };

  $scope.closeSubTitle = function (){
    var e1 = document.getElementById('close_sub_title');
    var sub_title = e1.getAttribute('data-close-sub-title');
    if(mass.close_sub_title)
      return mass.close_sub_title;
    else
      return sub_title;
  };

  $scope.referralBtnText = function (defualt_text) {
    if(mass.referral_btn_text)
      return mass.referral_btn_text;
    else
      return defualt_text;
  }

  function resetAllReplies(replies) {
    _.each(replies, function (r) {
      r.answer = null;
    });
    return replies;
  }

  /////////////////////////////////////////////////////////////////////////////
  //  Handle results returning from the get_questionnaire_employees API
  /////////////////////////////////////////////////////////////////////////////
  function handleEmployeesResult(response) {
    console.log(response)
    $scope.employees = response.data;
    _.each($scope.employees, function (e) {
      e.id = +e.id;
      e.qp_id = +e.qp_id;
    });
    console.log(getSearchList())
    $scope.search_list = getSearchList();
    console.log($scope.search_list)
    console.log('$scope.search_list')
  }

  /////////////////////////////////////////////////////////////////////////////
  //  Handle results returning from the get_next_question API
  /////////////////////////////////////////////////////////////////////////////
  function handleGetNextQuestionResult(response, options) {
    console.log(response)
    $scope.current_question_position = response.data.current_question_position;

    if (response.data.current_question_position == 1 && response.data.is_snowball_q) {
      $scope.is_snowball_q_first_step = true;
    } else {
      $scope.is_snowball_q_first_step = false;
      $scope.showModal = false;
    }
    console.log(response.data.current_employee_id)
    $scope.current_employee_id = response.data.current_emp_id;
    $scope.is_snowball_q = response.data.is_snowball_q;
    $scope.snowball_enable_autocomplete = response.data.snowball_enable_autocomplete;
    $scope.container = $document[0].querySelector('.question-container');
    $scope.questionnaire_id = response.data.questionnaire_id;
    $scope.original_data = response.data;
    var employee_ids_in_question =  _.pluck(response.data.replies, 'employee_details_id');
    var employees_for_question = _.filter($scope.employees, function (e) { return _.include(employee_ids_in_question, e.id); });
    $scope.workers = employees_for_question;
    $scope.unselected_workers = $scope.workers;

    if (options && options.reset_question) {
      $scope.original_data.replies = resetAllReplies($scope.original_data.replies);
      $scope.currentlyFocusedEmployeeId = -1;
    }
    mobileAppService.setIndexOfCurrentQuestion(response.data.current_question_position);

    if (response.data.min === response.data.max) {
      mobileAppService.setQuestionTypeClearScreen();
    } else {
      mobileAppService.setQuestionTypeMinMax(response.data.min, response.data.max);
    }
    $scope.questions_to_answer = format_questions_to_answer(response.data);
    $scope.getGroups();
    $scope.paramsForAutoCompliteFirstName = {sid : $scope.questionnaire_id, field : 'f', term : '', token : mobileAppService.getToken()};
    $scope.paramsForAutoCompliteLastName = {sid : $scope.questionnaire_id, field : 'l', term : '', token : mobileAppService.getToken()};
    //$scope.getAutoCompleteList($scope.paramsForAutoCompliteFirstName);

    buildQuestionResponseStructs();
    mobileAppService.updateState(response.data);
    if(response.data.is_contain_funnel_question && !response.data.is_funnel_question)
      $scope.full_search = false;
    console.log('handle scope result after all')
    console.log($scope)
  }

  /////////////////////////////////////////////////////////////////////////////
  //  Handle results returning from the close_question API
  /////////////////////////////////////////////////////////////////////////////
  function handleCloseQuestionResult(response) {
    console.log(response)
    if (response === undefined) { return; }

    var res = response.data;
      console.log(res)
     if(res && res.status === 'fail') {
      console.error('Question was not closed becuase: ', res.reason);
    }
    // $scope.container.style.visibility = 'visible';

  }

  function syncDataWithServer(params, options) {
    console.log(params, options)
    if (options && options.continue_later) {
      params.continue_later = true;
    } else {
      params.continue_later = false;
    }
    // if (!params.is_selection_question) {
      var p1 = ajaxService.get_employees(params);
    console.log(p1)
      // The reason for doing this here is that the first time this function is
      // called we don't want to close the question, but in subsequent calls we
      // do. At any rate we can only call get_next_question if the previouse
      // question was already called.
    console.log(params.responses)
      if (params.responses) {
        delete params.responses;
      }
    console.log(params.tiny_array)
      if (params.tiny_array) {
        delete params.tiny_array;
      }

      if (params.employees) {
        delete params.employees;
      }

      var p2 = (options && options.close_question ?
          ajaxService.close_question(params) :
          Promise.resolve());
    console.log(p2)
    console.log(options)

      if (options && options.reset) {
        $q.all([
          p1.then(function (response) {
            handleEmployeesResult(response);
          }),
          p2.then(function (response) {
            handleCloseQuestionResult(response);
          }).then(function () {
            return ajaxService.get_next_question(params);
          }).then(function (response) {
            console.log(response)
            handleGetNextQuestionResult(response, options);
          })
        ]).then(function () {
          if ($scope.original_data.status === 'done') {
            mobileAppService.setFinishView();
          } else {
            // if ($scope.original_data.is_selection_question) {
            //   console.log($scope.r)
            //   $scope.show_popup = true;
            //   $scope.show_full_question = true;
            //   console.log($scope.container)
            //   $scope.loaded[0] = true;
            //   // $scope.show_question = true;
            //   // $scope.question_text = $scope.original_data.question_text;
            //   //
            //   // $scope.options = $scope.original_data.options;
            // } else {
              console.log('This is responses in sync Data with server')
              console.log($scope.responses[_.keys($scope.responses)[0]].responses.length)
              console.log($localStorageService.getObject('responses'))
              console.log($scope.current_question_position)
              console.log($localStorageService.getObject('responses') == null || $localStorageService.getObject('responses').length == 0)
              if (mass.current_question_position > 1 && $scope.responses[_.keys($scope.responses)[0]].responses.length == 0 && $localStorageService.getObject('responses') !== null) {
                console.log('syncDataWithServer if (mass.current_question_position')
                $scope.responses[_.keys($scope.responses)[0]].responses = $localStorageService.getObject('responses');
                //console.log($scope.responses[_.keys($scope.responses)[0]].responses)
              }
              // It means that we dont have reponses array, it's null or empty array, need to transform replies object to be reponses
              if ($scope.current_question_position > 1 && $scope.responses[_.keys($scope.responses)[0]].responses.length == 0 && ($localStorageService.getObject('responses') == null || $localStorageService.getObject('responses').length == 0)) {
                console.log('Transforming replies object to be responses array')
                console.log($scope.original_data.is_selection_question)
                $scope.original_data.replies.forEach(function (reply) {
                  var newUserResponse = {
                    employee_details_id: reply.employee_details_id,
                    employee_id: reply.e_id,
                    response: null
                  };
                  console.log(newUserResponse)
                  $scope.responses[_.keys($scope.responses)[0]].responses.push(newUserResponse)
                  console.log($scope.responses[_.keys($scope.responses)[0]].responses)
                });
              }

              $scope.r = $scope.responses[_.keys($scope.responses)[0]];
              console.log($scope.r)
              $scope.tiny_array = $scope.r.responses.slice(0, 10);
              console.log($scope.tiny_array)
              $scope.currentlyFocusedEmployeeId = $scope.tiny_array[0].employee_id;
              if (!options.reset_question) {
                console.log('debug part options.reset_question')
                $scope.show_popup = true;

                if (!($scope.isDisplaySafariMsg(navigator.userAgent)))
                  $scope.show_full_question = true;
                // $scope.container.style.visibility = 'visible';
                if ($scope.container !== null) {
                  $scope.percentageValue = -60;

                  var totalDuration = 500;
                  var intervalDuration = 10;
                  var steps = totalDuration / intervalDuration;
                  var incrementPerStep = Math.abs($scope.percentageValue / steps);

                  var intervalPromise = $interval(function () {
                    $scope.percentageValue += incrementPerStep;

                    if ($scope.container) {
                      $scope.container.style.transform = 'translateY(' + $scope.percentageValue + '%)';
                    }

                    if ($scope.percentageValue >= 0) {
                      $scope.percentageValue = 0;
                      if ($scope.container) {
                        $scope.container.style.transform = 'translateY(0%)';
                      }
                      $interval.cancel(intervalPromise);
                    }
                  }, intervalDuration);

                  $scope.$on('$destroy', function () {
                    $interval.cancel(intervalPromise);
                  });
                  $scope.container.showValue = true;
                }
              }
              $scope.loaded[0] = true;
              $scope.hhh = $scope.search_list();
            // }
          }
        });
      }
    // } else {
    //   console.log(params)
    //   ajaxService.get_next_question(params)
    //       .then(function(response) {
    //         handleGetNextQuestionResult(response, options);
    //       });
    // }

  }

  function closeSearchWhenClickingElsewhere(event, callbackOnClose) {
    var clickedElement = event.target;
    if (!clickedElement) return;
    var elementClasses = clickedElement.classList;
    var clickedOnSearchDrawer = elementClasses.contains('search-btn') || elementClasses.contains('searchInput') || elementClasses.contains('search-result') || (clickedElement.parentElement !== null && (clickedElement.parentElement.classList.contains('search-item') || clickedElement.parentElement.classList.contains('right-search-input') ||  clickedElement.parentElement.classList.contains('search-btn')));
    if (!clickedOnSearchDrawer) {
      callbackOnClose();
      return;
    }
  }


  function updateReplies(params) {
    ajaxService.update_replies(params).then(function(res) {
      console.log('update_replies() - res: ', res);
    });
  }

  $scope.loadMore = function () {
    $log.debug('In loadMore()');
    var startIndex = $scope.tiny_array.length;
    $scope.tiny_array = _.union($scope.tiny_array, $scope.r.responses.slice(startIndex, startIndex + 10));
  };

  function updateScopeResponsesFromAnswers() {
    var responses = $scope.responses[_.keys($scope.responses)[0]].responses;
    console.log(responses)
    // The arrays: responses and $scope.original_data.replies do not have the same size,
    // so we fix it here.
    var updated_replies = [];
    _.forEach($scope.original_data.replies, function (r) {
      // Find the right employee
      var response = _.find(responses, function(resp) { return resp.employee_id === r.e_id; });

      if ( response !== undefined ) {
        r.answer = response.response;
        updated_replies.push(r);
      }
    });
    console.log(updated_replies)
    $scope.original_data.replies = updated_replies;

  }

  $scope.minMaxOnFinish = function () {
    $log.debug('In minMaxOnFinish()');
    console.log($scope.questionnaire_id)
    var storageData = $localStorageService.getObject($scope.questionnaire_id);
    console.log(storageData)
    var num_reps = mass.num_replies_true + mass.num_replies_false;
    console.log(num_reps)
    // console.log('im here, after checking all employee')
    console.log($scope.canFinish())
    if (!$scope.canFinish()) {
      $scope.clicked_on_next[0] = true;
    } else {
      console.log($scope.current_question_position === 1)
      console.log(num_reps == $scope.original_data.answered)
      console.log($scope.first_q)
      console.log($scope.is_snowball_q )
      // $scope.init($scope.original_data, {close_question: true});
      //
      // $scope.currentlyFocusedEmployeeId = -1;
      console.log($scope.current_question_position)
      console.log($scope.is_snowball_q)

      //here need to make check if user add new employees
      // thats mean we on first q and it's snowball q, and user didn't add any new user
      if ($scope.current_question_position === 1 && $scope.is_snowball_q && (num_reps == $scope.original_data.answered) && $scope.first_q) {
        console.log('detecting that user back to first q and did not added any new employees')
        updateScopeResponsesFromAnswers();
        // var originalData = $localStorageService.getObject('original_data')
        $scope.returnToCachedQ();

      } else {
        updateScopeResponsesFromAnswers();
        $scope.init($scope.original_data, {close_question: true});
      }
      $scope.currentlyFocusedEmployeeId = -1;
      if ($scope.current_question_position === 1 && $scope.is_snowball_q) {
        var client_max_replies = mass.client_max_replies;

        if (storageData) {
          storageData.answered = num_reps;
          storageData.client_max_replies = client_max_replies;
        } else {
          storageData = {'answered': num_reps, 'client_max_replies': client_max_replies};
        }

        $localStorageService.saveObject($scope.questionnaire_id, storageData);
      }
    }
  };
  $scope.closeSearchResult = function () {
    $scope.toggleSearchInput()
    // $scope.search_input.text = '';
  }

  $scope.toggleSearchInput = function () {
    $scope.searchListOpen = !$scope.searchListOpen;
    if( $scope.searchListOpen){
      console.log('here')
      $scope.hhh = $scope.search_list();
      $window.onclick = function (event) {
        closeSearchWhenClickingElsewhere(event, $scope.toggleSearchInput);
      };    
    }else {
      $scope.search_input.text = '';
      $scope.search_input.firstname = '';
      $scope.search_input.lastname = '';
      $scope.searchListOpen = false;
      $window.onclick = null;
      $scope.$evalAsync();
    }
  }

  $scope.clearScreenOnFinish = function () {
    if (!$scope.canFinish()) { return; }
    updateScopeResponsesFromAnswers();
    console.log('calling clearScreenOnFinish trying to get original data')
    console.log($scope.original_data);
    $scope.init($scope.original_data, {close_question: true});
  };

  $scope.continueLater = function () {
    $log.debug('In continueLater()');
    updateScopeResponsesFromAnswers();
    $scope.state_saved[0] = true;
    $scope.original_data.token = $scope.params.token;
    updateReplies($scope.original_data);
  };

  $scope.getEmployeeIdByName = function (name) {
    return (_.find($scope.unselected_workers, { name: name })).id;
  };

  $scope.findOrLoadAndFind = function (id) {
    $log.debug('In findOrLoadAndFind()');
    var foundItem = _.find($scope.tiny_array, { 'employee_details_id': id });
    if (!foundItem && $scope.tiny_array.length !== $scope.r.responses.length) {
      $scope.loadMore();
      return $scope.findOrLoadAndFind(id);
    } return foundItem;
  };

  $scope.isChoseBySearch = function () {
    return $scope.is_chose_by_search;
  }
  $scope.getChosenEmployee = function() {
    if($scope.chosen_employee)
      return $scope.chosen_employee.name;;
    return '';
  }
  $scope.showConfirmBox = function($item) {
    var emp = _.find($scope.employees, { 'id': $item.id });
    $scope.chosen_employee = emp;
    $scope.is_chose_by_search = true;
    $scope.show_popup = true;
    $scope.closeSearchResult()

  }
  $scope.onCancel = function() {
    $scope.chosen_employee = undefined;
    $scope.is_chose_by_search = false;
    $scope.show_popup = false;
    // $scope.searchListOpen = false;

  }
  $scope.searchFunc = function () {
    if ($scope.search_input.lastname === undefined){
      $scope.search_input.lastname = ''
    }
    if ($scope.search_input.firstname === undefined){
      $scope.search_input.firstname = ''
    }
   // $scope.hhh = $scope.search_list();
  }

  $scope.showAutoCompleteList = function (field) {
    if ($scope.snowball_enable_autocomplete){
      if (field == 'firstname' && $scope.search_input.firstname.length > 0) $scope.showFirstNameList = !$scope.showFirstNameList
      if (field == 'lastname' &&  $scope.search_input.lastname.length > 0) $scope.showLastNameList = !$scope.showLastNameList
    }
  }

  $scope.chooseAndHide = function (name, field) {
    if (field == 'firstname')  $scope.search_input.firstname = name ; $scope.showFirstNameList = false;
    if (field == 'lastname')  $scope.search_input.lastname = name ; $scope.showLastNameList = false;
  }

  $scope.checkIfAutoCompleteListIsOpenAndCloseIt = function (event) {
    var clickedElement = event.target;

    var hasClass = clickedElement.classList.contains('search-item') ||
        clickedElement.classList.contains('search-emp-name') ||
        clickedElement.classList.contains('emp-name') ||
        clickedElement.closest('.search-item') ||
        clickedElement.closest('.search-emp-name') ||
        clickedElement.closest('.emp-name');

    if (!hasClass) {
      $scope.showFirstNameList = false;
      $scope.showLastNameList = false;
      //$scope.$apply();
    }
  }

  $scope.searchAutocompleteFunc = function (field) {
    if ($scope.snowball_enable_autocomplete) {
      const isFirstName = field === 'firstname';
      const params = isFirstName ? $scope.paramsForAutoCompliteFirstName : $scope.paramsForAutoCompliteLastName;
      const searchTerm = isFirstName ? $scope.search_input.firstname : $scope.search_input.lastname;
      const autocompleteListType = isFirstName ? 'firstnames' : 'lastnames';
      const showListType = isFirstName ? 'showFirstNameList' : 'showLastNameList';

      params.term = searchTerm;
      $scope.getAutoCompleteList(params).then(function(data) {
        $scope.autocomplete[autocompleteListType] = data;
        $scope[showListType] = true;

        if (!isFirstName) {
          console.log($scope.autocomplete.lastnames);
        } else {
          console.log($scope.autocomplete.firstnames)
        }
      });
    }
  }

  $scope.employee = {
    firstname: '',
    lastname: '',
    department: ''
  };

  // Depatments custom dropdown part

  $scope.departments = [{id: 1, name: 'Department1'}, {id: 2, name: 'Department2'}] // For now it's manual values

  //Departments dropdown part end

  // Autcomplete data for first/lastnames

  $scope.showFirstNameList = false;
  $scope.showLastNameList = false;

  $scope.autocomplete = {};
  $scope.autocomplete.firstnames = {}
  $scope.autocomplete.lastnames = {}

  $scope.clearEmployeeObject = function () {
    $scope.employee.firstname = '';
    $scope.employee.lastname = '';
    $scope.employee.department = '';
    $scope.search_input.firstname = '';
    $scope.search_input.lastname = '';
  }

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

  $scope.showModal = false;

  $scope.addEmployeeModalFunc = function() {
    $scope.splitOrAddSearchResultToForm()
    $scope.showModal = !$scope.showModal;
  };

  $scope.closeModalFunc = function() {
    $scope.showModal = !$scope.showModal;
  };

  // Creating Employee

  $scope.submitUnverifiedEmployeeForm = function() {
    var data = {
      e_first_name: $scope.search_input.firstname,
      e_last_name: $scope.search_input.lastname,
      e_group: $scope.employee.department,
      qpid : $scope.original_data.qpid,
      token : $scope.params.token
    };
    console.log(data)
    ajaxService.createUnverifiedEmployee(data).then(function(response) {
      console.log("Response:", response.data);
      // For some reason question_id is undefined;
      var newUserResponse = {
        employee_details_id: response.data.e_id,
        employee_id: response.data.qpid,
        response: null
      };
      var newEmployeeObject = {
        id: response.data.e_id,
        name: response.data.name,
        qp_id:response.data.qpid,
        role: "Employee",
        image_url: response.data.image_url
      }
      var newUserDataRepliesResponse = {
        e_id: response.data.qpid,
        employee_details_id: response.data.e_id,
        response: null
      };

      // Here we modify all arrays and objects for display new employee
      const hasEmployeeDetailsId = $scope.tiny_array.some(item => item.employee_details_id === response.data.e_id);
      const existsInResponses = $scope.responses.undefined.responses.some(item => item.employee_details_id === newUserResponse.employee_details_id);

      if (!hasEmployeeDetailsId) {
        $scope.employees.push(newEmployeeObject)
        $scope.tiny_array.push(newUserResponse)

        if (!existsInResponses) {
          $scope.responses.undefined.responses.push(newUserResponse);
        }

        $scope.original_data.replies.push(newUserDataRepliesResponse);
      }

      $scope.currentlyFocusedEmployeeId = $scope.nextEmployeeIdWithoutResponseForQuestion(undefined, response.data.qpid);
      $scope.clearEmployeeObject();
      $scope.onUserResponse(undefined, newUserResponse.employee_id, true, newUserResponse.employee_details_id)

      if (mass.client_max_replies == undefined && $scope.first_q){
        console.log('here am i')
        mass.client_max_replies = $scope.first_q.max;
      }
      var num_reps = mass.num_replies_true + mass.num_replies_false;
      canUserReturnToFirstQuestion(mass.num_replies_true,mass.client_max_replies)

    }).catch(function(error) {
      console.error("Error:", error);
    });
  };

    $scope.submitInterestQuestionForm = function () {
      console.log($scope.interestQuestion.selectedOption);
      console.log($scope.r.selection_question_options)
      $scope.findSelectedOptionIndex($scope.interestQuestion.selectedOption)

      if ($scope.selectedOptionIndex !== -1) {
        console.log($scope.r)
        console.log($scope.selectedOptionIndex)
        const selectedOption = $scope.r.selection_question_options[$scope.selectedOptionIndex];
        console.log(selectedOption)
        selectedOption.value = true;
        console.log(mass)
        const masSelect = mass.selection_question_options[$scope.selectedOptionIndex];
        masSelect.value = true;
      }
      const selectedParam = $scope.interestQuestion.selectedOption;
      var data = {
        [$scope.selectedOptionIndex]: $scope.interestQuestion.selectedOption,
        qpid: $scope.original_data.qpid,
        token: $scope.params.token
      };
      // ajaxService.createUnverifiedEmployee(data).then(function(response) {
      //   console.log(response)
      //   var newEmployeeObject = {
      //     id: response.data.e_id,
      //     name: response.data.name,
      //     qp_id:response.data.qpid,
      //     role: "Employee",
      //     image_url: response.data.image_url
      //   }
      //   $scope.employees.push(newEmployeeObject)
      // })
      console.log(data)
      mass.num_replies_true = 1;
      var isFinished = $scope.canFinish();
      console.log(isFinished)
      canUserReturnToFirstQuestion(mass.num_replies_true,mass.client_max_replies)
    };

    $scope.interestQuestion = {
      selectedOption: ''
    };

    $scope.findSelectedOptionIndex = function(name) {
      console.log(name)
      console.log($scope.r.selection_question_options.length)
      console.log($scope.r.selection_question_options[1].name)
      for (var i = 0; i < $scope.r.selection_question_options.length; i++) {
        console.log($scope.r.selection_question_options[i].name == name)
        console.log($scope.r.selection_question_options[i])
        if ($scope.r.selection_question_options[i].name == name) {
          console.log($scope.r.selection_question_options[i].name)
          $scope.selectedOptionIndex = i;
          console.log($scope.selectedOptionIndex)
          break;
        }
      }
    };

    function canUserReturnToFirstQuestion(num_replies, max_replies){
    console.log('calling canUserReturnToFirstQuestion ')
    console.log(num_replies, max_replies)
    if (num_replies < max_replies) {
      return $scope.can_return_to_first_q = true ;
    }

    return $scope.can_return_to_first_q = false;
  }

  $scope.getGroups = function () {
    var param = {qid : $scope.questionnaire_id, token: mobileAppService.getToken()}
    ajaxService.getGroups(param).then(function(response) {
      $scope.departments = response.data.groups;
    })
  }

  $scope.getAutoCompleteList = function (params) {
    return ajaxService.getAutoCompleteData(params).then( function (response) {
      return response.data.data
    })
  }


  $scope.onSelect = function () {
    var emp = $scope.chosen_employee;
    // var emp = _.find($scope.employees, { 'id': $item.id });
    // $scope.chosen_employee = emp;
    // $scope.is_chose_by_search = true;
    // $scope.show_popup = true;
  //  if()
    // if (confirm("האם את/ה בטוח/ה כי ברצונך להוסיף את המשתתף לבחירתך?")) {
    //   console.log('emp: ', emp)
    //   $log.debug('In onSelect()');
      if (_.any($scope.r.responses, function (r) { return r.employee_details_id === emp.id; })) {
        // var employee_with_focus =  $scope.findOrLoadAndFind($item.id);
        // $scope.currentlyFocusedEmployeeId = employee_with_focus.employee_id;
      } else {
        $scope.search_added_emps.push(emp.qp_id);
        $scope.r.responses.splice(0, 0, { employee_id: emp.qp_id, employee_details_id: emp.id });
        $scope.tiny_array.splice(0, 0, { employee_id: emp.qp_id, employee_details_id: emp.id });
        // $scope.currentlyFocusedEmployeeId = emp.qp_id;
      }
      $scope.onUserResponse(undefined, emp.qp_id, true, undefined,false);
    // }
      console.log('here on Select')
      if ($scope.is_snowball_q_first_step){
        $scope.hhh = $scope.search_list();
      }
      $scope.show_popup = false;
      $scope.is_chose_by_search = false;
      $scope.chosen_employee = undefined;
      // $scope.searchListOpen = false;
    return;
    // $log.debug('In onSelect()');
    // if (_.any($scope.r.responses, function (r) { return r.employee_details_id === $item.id; })) {
    //   var employee_with_focus =  $scope.findOrLoadAndFind($item.id);
    //   $scope.currentlyFocusedEmployeeId = employee_with_focus.employee_id;
    // } else {
    //   var emp = _.find($scope.employees, { 'id': $item.id });
    //   $scope.search_added_emps.push(emp.qp_id);
    //   $scope.r.responses.splice(0, 0, { employee_id: emp.qp_id, employee_details_id: emp.id });
    //   $scope.tiny_array.splice(0, 0, { employee_id: emp.qp_id, employee_details_id: emp.id });
    //   $scope.currentlyFocusedEmployeeId = emp.qp_id;
    // }
  };

  $scope.matchString = function (pattern, str) {
    if (pattern === undefined || pattern === null || pattern === "") { return true; }
    return (str.toLowerCase().indexOf(pattern.toLowerCase()) >= 0);
  };

  $scope.getParticipantId = function () {
    //return $scope.original_data.token
    return $scope.original_data.external_id;
  }

  $scope.display_search = function() {
    if(mass.is_contain_funnel_question && !mass.is_funnel_question)
      return false;
    return true;
  };

  $scope.isDisplaySafariMsg = function () {
     // var ua = (navigator.userAgent)
     // if(mobileAppService.is_display_safari_msg() && mobileAppService.isSafari(ua))
     //    return true
      return false
  }

  $scope.onCancelSafariMsg = function() {
    mobileAppService.not_display_safari_msg()
    $scope.show_popup = false;
    $scope.show_full_question = true

  }

  $scope.copyLink = function() {
    $scope.link_copied = true
    navigator.clipboard.writeText(window.location.href)
    $timeout(function () {
      $scope.link_copied = false;
    }, 1500);
  }

  $scope.init = function (next_question_params, options) {
    console.log(next_question_params, options)
    $scope._ = _;
    $scope.search_added_emps = [];
    options = options || {};
    $scope.undo_worker_stack = [];
    $scope.clicked_on_next = [false];
    $scope.state_saved = [false];
    $scope.loaded = [false];
    $scope.show_popup = false;
    $scope.is_chose_by_search = false;
    $scope.chosen_employee = undefined;
    $scope.searchListOpen = false;
    $scope.current_avatar_color = 0;
    $scope.full_search = true;
    $scope.link_copied = false

    setTimeout(function () {
      $scope.heightOfContainer = document.getElementById('main_container').getBoundingClientRect().height;
    }, 0);

    $scope.swipe = {
      right: false,
      left: false,
    };
    $scope.params = next_question_params || { token: mobileAppService.getToken() };
    $scope.params.token = mobileAppService.getToken();
    $scope.paramsForGettingFirstQ = {
      token : $scope.params.token,
      q_num : 1
    }
    console.log($scope.params)
    // let selectionQuestion;
    // if (next_question_params !== undefined && next_question_params.is_selection_question){
    //   selectionQuestion = next_question_params.is_selection_question;
    // }
    var opts = {
      continue_later: !next_question_params,
      reset: true,
      reset_question: options.reset_question,
      close_question: (options.close_question === true ? true : false)
    };
    console.log(opts)

    syncDataWithServer($scope.params, opts);
    $scope.search_input = { text: '', lastname: '', firstname: ''};
    $scope.workers = null;
    $scope.unselected_workers = null;
    $scope.names = {};
    console.log(mass)
    if ($scope.first_q == undefined && mobileAppService.getIndexOfCurrentQuestion() > 1 && mobileAppService.getIsSnowball()) {
      console.log('on init')
      console.log(mass)
      canUserReturnToFirstQuestion(mass.client_min_replies,mass.max)
    }
    _.forEach($scope.workers, function (worker) { $scope.names[worker.id] = worker.name; });
  };
}]);
