*&---------------------------------------------------------------------*
*&  Include           ZABAPGIT_PAGE_STAGE
*&---------------------------------------------------------------------*

CLASS lcl_gui_page_stage DEFINITION FINAL INHERITING FROM lcl_gui_page.

  PUBLIC SECTION.
    CONSTANTS: BEGIN OF c_action,
                 stage_all    TYPE string VALUE 'stage_all',
                 stage_commit TYPE string VALUE 'stage_commit',
               END OF c_action.

    METHODS:
      constructor
        IMPORTING
          io_repo         TYPE REF TO lcl_repo_online
        RAISING   lcx_exception,
      lif_gui_page~on_event REDEFINITION.

  PROTECTED SECTION.
    METHODS:
      render_content REDEFINITION,
      scripts        REDEFINITION.

  PRIVATE SECTION.
    DATA: mo_repo  TYPE REF TO lcl_repo_online,
          ms_files TYPE ty_stage_files,
          mo_stage TYPE REF TO lcl_stage,
          mv_ts    TYPE timestamp.

    METHODS:
      render_list
        RETURNING VALUE(ro_html) TYPE REF TO lcl_html,
      render_file
        IMPORTING iv_context     TYPE string
                  is_file        TYPE ty_file
                  is_item        TYPE ty_item OPTIONAL
        RETURNING VALUE(ro_html) TYPE REF TO lcl_html,
      render_menu
        RETURNING VALUE(ro_html) TYPE REF TO lcl_html,
      read_last_changed_by
        IMPORTING is_file        TYPE ty_file
        RETURNING VALUE(rv_user) TYPE xubname.

    METHODS process_stage_list
      IMPORTING it_postdata TYPE cnht_post_data_tab
      RAISING   lcx_exception.
    METHODS build_menu
      RETURNING VALUE(ro_menu) TYPE REF TO lcl_html_toolbar.

ENDCLASS.

CLASS lcl_gui_page_stage IMPLEMENTATION.

  METHOD constructor.

    super->constructor( ).

    ms_control-page_title = 'STAGE'.
    mo_repo               = io_repo.
    ms_files              = lcl_stage_logic=>get( mo_repo ).

    CREATE OBJECT mo_stage
      EXPORTING
        iv_branch_name = io_repo->get_branch_name( )
        iv_branch_sha1 = io_repo->get_sha1_remote( ).

    GET TIME STAMP FIELD mv_ts.

    ms_control-page_menu  = build_menu( ).

  ENDMETHOD.

  METHOD build_menu.

    CREATE OBJECT ro_menu.

    IF lines( ms_files-local ) > 0.
      ro_menu->add( iv_txt = |All diffs|
                    iv_act = |{ gc_action-go_diff }?key={ mo_repo->get_key( ) }| ).
    ENDIF.

  ENDMETHOD. "build_menu

  METHOD lif_gui_page~on_event.

    FIELD-SYMBOLS: <ls_file> LIKE LINE OF ms_files-local.

    CASE iv_action.
      WHEN c_action-stage_all.
        mo_stage->reset_all( ).
        LOOP AT ms_files-local ASSIGNING <ls_file>.
          mo_stage->add( iv_path     = <ls_file>-file-path
                         iv_filename = <ls_file>-file-filename
                         iv_data     = <ls_file>-file-data ).
        ENDLOOP.
      WHEN c_action-stage_commit.
        mo_stage->reset_all( ).
        process_stage_list( it_postdata ).
      WHEN OTHERS.
        RETURN.
    ENDCASE.

    CREATE OBJECT ei_page TYPE lcl_gui_page_commit
      EXPORTING
        io_repo  = mo_repo
        io_stage = mo_stage.

    ev_state = gc_event_state-new_page.

  ENDMETHOD.

  METHOD process_stage_list.

    DATA: lv_string TYPE string,
          lt_fields TYPE tihttpnvp,
          ls_file   TYPE ty_file.

    FIELD-SYMBOLS: <ls_file> LIKE LINE OF ms_files-local,
                   <ls_item> LIKE LINE OF lt_fields.

    CONCATENATE LINES OF it_postdata INTO lv_string.
    lt_fields = cl_http_utility=>if_http_utility~string_to_fields( |{ lv_string }| ).

    IF lines( lt_fields ) = 0.
      lcx_exception=>raise( 'process_stage_list: empty list' ).
    ENDIF.

    LOOP AT lt_fields ASSIGNING <ls_item>.

      lcl_path=>split_file_location( EXPORTING iv_fullpath = <ls_item>-name
                                     IMPORTING ev_path     = ls_file-path
                                               ev_filename = ls_file-filename ).
      CASE <ls_item>-value.
        WHEN lcl_stage=>c_method-add.
          READ TABLE ms_files-local ASSIGNING <ls_file>
            WITH KEY file-path     = ls_file-path
                     file-filename = ls_file-filename.
          ASSERT sy-subrc = 0.
          mo_stage->add(    iv_path     = <ls_file>-file-path
                            iv_filename = <ls_file>-file-filename
                            iv_data     = <ls_file>-file-data ).
        WHEN lcl_stage=>c_method-ignore.
          mo_stage->ignore( iv_path     = ls_file-path
                            iv_filename = ls_file-filename ).
        WHEN lcl_stage=>c_method-rm.
          mo_stage->rm(     iv_path     = ls_file-path
                            iv_filename = ls_file-filename ).
        WHEN lcl_stage=>c_method-skip.
          " Do nothing
        WHEN OTHERS.
          lcx_exception=>raise( |process_stage_list: unknown method { <ls_item>-value }| ).
      ENDCASE.
    ENDLOOP.

  ENDMETHOD.        "process_stage_list

  METHOD render_list.

    FIELD-SYMBOLS: <ls_remote> LIKE LINE OF ms_files-remote,
                   <ls_local>  LIKE LINE OF ms_files-local.

    CREATE OBJECT ro_html.

    ro_html->add( '<table id="stageTab" class="stage_tab">' ).

    " Local changes
    LOOP AT ms_files-local ASSIGNING <ls_local>.
      AT FIRST.
        ro_html->add('<thead><tr class="local">').
        ro_html->add('<th>Type</th>').
        ro_html->add('<th>Files to add (click to see diff)</th>' ).
        ro_html->add('<th>Changed by</th>').
        ro_html->add('<th></th>' ). " Status
        ro_html->add('<th class="cmd">&#x2193;<a>add</a>/<a>reset</a>&#x2193;</th>' ).
        ro_html->add('</tr></thead>').
        ro_html->add('<tbody>').
      ENDAT.

      ro_html->add( render_file(
        iv_context = 'local'
        is_file    = <ls_local>-file
        is_item    = <ls_local>-item ) ). " TODO Refactor, unify structure

      AT LAST.
        ro_html->add('</tbody>').
      ENDAT.
    ENDLOOP.

    " Remote changes
    LOOP AT ms_files-remote ASSIGNING <ls_remote>.
      AT FIRST.
        ro_html->add( '<thead><tr class="remote">' ).
        ro_html->add( '<th></th>' ). " Type
        ro_html->add( '<th colspan="2">Files to remove or non-code</th>' ).
        ro_html->add( '<th></th>' ). " Status
        ro_html->add( '<th class="cmd">' &&
                      '&#x2193;<a>ignore</a><a>remove</a><a>reset</a>&#x2193;</th>' ).
        ro_html->add( '</tr></thead>' ).
        ro_html->add( '<tbody>' ).
      ENDAT.

      ro_html->add( render_file(
        iv_context = 'remote'
        is_file    = <ls_remote> ) ).

      AT LAST.
        ro_html->add('</tbody>').
      ENDAT.
    ENDLOOP.

    ro_html->add( '</table>' ).

  ENDMETHOD.      "render_lines

  METHOD render_file.

    DATA: lv_param    TYPE string,
          lv_filename TYPE string.

    CREATE OBJECT ro_html.

    lv_filename = is_file-path && is_file-filename.

    ro_html->add( |<tr class="{ iv_context }">| ).

    CASE iv_context.
      WHEN 'local'.
        lv_param    = lcl_html_action_utils=>file_encode( iv_key  = mo_repo->get_key( )
                                                          ig_file = is_file ).
        lv_filename = lcl_html=>a( iv_txt = lv_filename
                                   iv_act = |{ gc_action-go_diff }?{ lv_param }| ).
        ro_html->add( |<td class="type">{ is_item-obj_type }</td>| ).
        ro_html->add( |<td class="name">{ lv_filename }</td>| ).
        ro_html->add( |<td class="user">{ read_last_changed_by( is_file ) }</td>| ).
      WHEN 'remote'.
        ro_html->add( '<td class="type">-</td>' ).  " Dummy for object type
        ro_html->add( |<td class="name">{ lv_filename }</td>| ).
        ro_html->add( '<td></td>' ).                " Dummy for changed-by
    ENDCASE.

    ro_html->add( |<td class="status">?</td>| ).
    ro_html->add( '<td class="cmd"></td>' ). " Command added in JS
    ro_html->add( '</tr>' ).

  ENDMETHOD.  "render_file

  METHOD render_content.

    CREATE OBJECT ro_html.

    ro_html->add( '<div class="repo">' ).
    ro_html->add( lcl_gui_chunk_lib=>render_repo_top( mo_repo ) ).
    ro_html->add( lcl_gui_chunk_lib=>render_js_error_banner( ) ).
    ro_html->add( render_menu( ) ).
    ro_html->add( render_list( ) ).
    ro_html->add( '</div>' ).

  ENDMETHOD.      "render_content

  METHOD render_menu.

    DATA lv_local_count TYPE i.

    CREATE OBJECT ro_html.
    lv_local_count = lines( ms_files-local ).

    ro_html->add( '<div class="paddings">' ).
    ro_html->add_a( iv_act   = 'errorStub(event)' " Will be reinit by JS
                    iv_typ   = gc_action_type-onclick
                    iv_id    = 'commitButton'
                    iv_style = 'display: none'
                    iv_txt   = 'Commit (<span id="fileCounter"></span>)'
                    iv_opt   = gc_html_opt-strong ) ##NO_TEXT.
    IF lv_local_count > 0.
      ro_html->add_a( iv_act = |{ c_action-stage_all }|
                      iv_id  = 'commitAllButton'
                      iv_txt = |Add all and commit ({ lv_local_count })| ) ##NO_TEXT.
    ENDIF.
    ro_html->add( '</div>' ).

    ro_html->add( '<div>' ).
    ro_html->add( '<input id="objectSearch" type="search" placeholder="Filter objects">' ).
    ro_html->add( '</div>' ).

  ENDMETHOD.      "render_menu

  METHOD scripts.

    CREATE OBJECT ro_html.

    ro_html->add( 'var gStageParams = {' ).
    ro_html->add( |  seed:            "stage{ mv_ts }",| ).
    ro_html->add( '  formAction:      "stage_commit",' ).

    ro_html->add( '  ids: {' ).
    ro_html->add( '    stageTab:      "stageTab",' ).
    ro_html->add( '    commitBtn:     "commitButton",' ).
    ro_html->add( '    commitAllBtn:  "commitAllButton",' ).
    ro_html->add( '    objectSearch:  "objectSearch",' ).
    ro_html->add( '    fileCounter:   "fileCounter"' ).
    ro_html->add( '  }' ).

    ro_html->add( '}' ).
    ro_html->add( 'var gHelper = new StageHelper(gStageParams);' ).

  ENDMETHOD.  "scripts

  METHOD read_last_changed_by.
    DATA: ls_local_file TYPE ty_file_item,
          lt_files_local type ty_files_item_tt.
    TRY.
        lt_files_local = mo_repo->get_files_local( ).
        READ TABLE lt_files_local INTO ls_local_file WITH KEY file = is_file.
        IF sy-subrc = 0.
          rv_user = lcl_objects=>changed_by( ls_local_file-item ).
        ENDIF.
      CATCH lcx_exception.
        CLEAR rv_user. "Should not raise errors if user last changed by was not found
    ENDTRY.

    rv_user = to_lower( rv_user ).
  ENDMETHOD.

ENDCLASS.
