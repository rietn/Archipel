/*
 * TNSampleTabModule.j
 *
 * Copyright (C) 2010 Antoine Mercadal <antoine.mercadal@inframonde.eu>
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */


@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>


TNArchipelTypePermissions        = @"archipel:permissions";

TNArchipelTypePermissionsList   = @"list";
TNArchipelTypePermissionsGet    = @"get";
TNArchipelTypePermissionsSet    = @"set";

TNArchipelPushNotificationPermissions   = @"archipel:push:permissions";


/*! @defgroup  permissionsmodule Module Permissions
    @desc This module allow to manages entity permissions
*/

/*! @ingroup permissionsmodule
    Permission module implementation
*/
@implementation TNPermissionsController : TNModule
{
    @outlet CPTextField             fieldJID                @accessors;
    @outlet CPTextField             fieldName               @accessors;
    @outlet CPButtonBar             buttonBarControl;
    @outlet CPScrollView            scrollViewPermissions;
    @outlet CPSearchField           filterField;
    @outlet CPView                  viewTableContainer;
    @outlet CPPopUpButton           buttonUser;

    CPTableView                     _tablePermissions;
    TNTableViewDataSource           _datasourcePermissions;
    CPArray                         _currentUserPermissions;
    CPImage                         _defaultAvatar;

}


#pragma mark -
#pragma mark Initialization

- (void)awakeFromCib
{
    _currentUserPermissions = [CPArray array];
    _defaultAvatar          = [[CPImage alloc] initWithContentsOfFile:[[CPBundle mainBundle] pathForResource:@"user-unknown.png"]];

    [viewTableContainer setBorderedWithHexColor:@"#C0C7D2"];

    _datasourcePermissions  = [[TNTableViewDataSource alloc] init];
    _tablePermissions       = [[CPTableView alloc] initWithFrame:[scrollViewPermissions bounds]];

    [scrollViewPermissions setAutoresizingMask: CPViewWidthSizable | CPViewHeightSizable];
    [scrollViewPermissions setAutohidesScrollers:YES];
    [scrollViewPermissions setDocumentView:_tablePermissions];

    [_tablePermissions setUsesAlternatingRowBackgroundColors:YES];
    [_tablePermissions setAutoresizingMask: CPViewWidthSizable | CPViewHeightSizable];
    [_tablePermissions setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];
    [_tablePermissions setAllowsColumnReordering:YES];
    [_tablePermissions setAllowsColumnResizing:YES];
    [_tablePermissions setAllowsEmptySelection:YES];


    var colName         = [[CPTableColumn alloc] initWithIdentifier:@"name"],
        colDescription  = [[CPTableColumn alloc] initWithIdentifier:@"description"],
        colValue        = [[CPTableColumn alloc] initWithIdentifier:@"state"],
        checkBoxView    = [CPCheckBox checkBoxWithTitle:@""];

    [colName setWidth:125];
    [[colName headerView] setStringValue:@"Name"];

    [colDescription setWidth:450];
    [[colDescription headerView] setStringValue:@"Description"];

    [colValue setWidth:30];
    [[colValue headerView] setStringValue:@""];

    [checkBoxView setAlignment:CPCenterTextAlignment];
    [checkBoxView setFrameOrigin:CPPointMake(10.0, 0.0)];
    [checkBoxView setTarget:self];
    [checkBoxView setAction:@selector(changePermissionsState:)];
    [colValue setDataView:checkBoxView];

    [_tablePermissions addTableColumn:colValue];
    [_tablePermissions addTableColumn:colName];
    [_tablePermissions addTableColumn:colDescription];


    [_datasourcePermissions setTable:_tablePermissions];
    [_datasourcePermissions setSearchableKeyPaths:[@"name", @"description"]];
    [_tablePermissions setDataSource:_datasourcePermissions];

    var saveButton       = [CPButtonBar plusButton];

    [saveButton setImage:[[CPImage alloc] initWithContentsOfFile:[[CPBundle mainBundle] pathForResource:@"button-icons/button-icon-save.png"] size:CPSizeMake(16, 16)]];
    [saveButton setTarget:self];
    [saveButton setAction:@selector(changePermissionsState:)];

    [buttonBarControl setButtons:[saveButton]];

    [filterField setTarget:_datasourcePermissions];
    [filterField setAction:@selector(filterObjects:)];

    [buttonUser setTarget:self];
    [buttonUser setAction:@selector(didCurrentUserChange:)];
}



#pragma mark -
#pragma mark TNModule overrides

/*! called when module is loaded
*/
- (void)willLoad
{
    [super willLoad];

    var center = [CPNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_didUpdateNickName:) name:TNStropheContactNicknameUpdatedNotification object:_entity];
    [center postNotificationName:TNArchipelModulesReadyNotification object:self];

    [self registerSelector:@selector(_didReceivePush:) forPushNotificationType:TNArchipelPushNotificationPermissions];

    [buttonUser removeAllItems];

    var items = [CPArray array],
        item = [[TNMenuItem alloc] init];
    [item setTitle:@"Me"];
    [item setObjectValue:[_connection JID]];

    [buttonUser addItem:item];
    [buttonUser addItem:[CPMenuItem separatorItem]];

    for (var i = 0; i < [[_roster contacts] count]; i++)
    {
        var contact = [[_roster contacts] objectAtIndex:i],
            item = [[TNMenuItem alloc] init],
            img = ([contact avatar]) ? [[contact avatar] copy] : _defaultAvatar;

        if ([_roster analyseVCard:[contact vCard]] == TNArchipelEntityTypeUser)
        {
            [img setSize:CPSizeMake(18, 18)];

            [item setTitle:@"  " + [contact nickname]]; // sic..
            [item setObjectValue:[contact JID]];
            [item setImage:img];
            [items addObject:item];
        }
    }

    var sortedItems = [CPArray array],
        sortFunction = function(a, b, context) {
        var indexA = [[a title] uppercaseString],
            indexB = [[b title] uppercaseString];

        if (indexA < indexB)
            return CPOrderedAscending;
        else if (indexA > indexB)
            return CPOrderedDescending;
        else
            return CPOrderedSame;
    };
    sortedItems = [items sortedArrayUsingFunction:sortFunction];

    for (var i = 0; i < [sortedItems count]; i++)
        [buttonUser addItem:[sortedItems objectAtIndex:i]];

    [self getUserPermissions:[[[buttonUser selectedItem] objectValue] bare]];

    [buttonUser addItem:[CPMenuItem separatorItem]];

    var item = [[TNMenuItem alloc] init];
    [item setTitle:@"Manual"];
    [item setObjectValue:nil];

    [buttonUser addItem:item]
}


/*! called when module becomes visible
*/
- (void)willShow
{
    [super willShow];

    [fieldName setStringValue:[_entity nickname]];
    [fieldJID setStringValue:[_entity JID]];
}

/*! called when module is unloaded
*/
- (void)willUnload
{
    [super willHide];

    [_datasourcePermissions removeAllObjects];
    [_tablePermissions reloadData]
}



#pragma mark -
#pragma mark Notification handlers

/*! called when entity' nickname changed
    @param aNotification the notification
*/
- (void)_didUpdateNickName:(CPNotification)aNotification
{
    if ([aNotification object] == _entity)
    {
       [fieldName setStringValue:[_entity nickname]]
    }
}

/*! called when an Archipel push is received
    @param somePushInfo CPDictionary containing the push information
*/
- (BOOL)_didReceivePush:(CPDictionary)somePushInfo
{
    var sender  = [somePushInfo objectForKey:@"owner"],
        type    = [somePushInfo objectForKey:@"type"],
        change  = [somePushInfo objectForKey:@"change"],
        date    = [somePushInfo objectForKey:@"date"];

    CPLog.info(@"PUSH NOTIFICATION: from: " + sender + ", type: " + type + ", change: " + change);

    [self getUserPermissions:[[[buttonUser selectedItem] objectValue] bare]];

    return YES;
}


#pragma mark -
#pragma mark Utilities

// put your utilities here


#pragma mark -
#pragma mark Actions


- (IBAction)changePermissionsState:(id)aSender
{
    [self changePermissionsState];
}

- (IBAction)didCurrentUserChange:(id)aSender
{
    if ([[[buttonUser selectedItem] respondsToSelector:@selector(objectValue)])
        [self getUserPermissions:[[[buttonUser selectedItem] objectValue] bare]];
}


#pragma mark -
#pragma mark XMPP Controls

/*! ask for existing permissions
*/
- (void)getPermissions
{
    var stanza = [TNStropheStanza iqWithType:@"get"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypePermissions}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypePermissionsList}];

    [_entity sendStanza:stanza andRegisterSelector:@selector(_didReceivePermissions:) ofObject:self];

}

/*! compute the answer containing the permissions
    @param aStanza TNStropheStanza containing the answer
*/
- (void)_didReceivePermissions:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        [_datasourcePermissions removeAllObjects];

        var permissions = [aStanza childrenWithName:@"permission"];

        for (var i = 0; i < [permissions count]; i++)
        {
            var permission      = [permissions objectAtIndex:i],
                name            = [permission valueForAttribute:@"name"],
                description     = [permission valueForAttribute:@"description"],
                state           = [_currentUserPermissions containsObject:name] ? CPOnState : CPOffState;
            var newPermission = [CPDictionary dictionaryWithObjectsAndKeys:name, @"name", description, @"description", state, "state"];
            [_datasourcePermissions addObject:newPermission];
        }

        [_tablePermissions reloadData];
    }
    else
    {
        [self handleIqErrorFromStanza:aStanza];
    }
}

/*! ask for permissions of given user
    @param aUser the user you want the permissions
*/
- (void)getUserPermissions:(CPString)aUser
{
    var stanza = [TNStropheStanza iqWithType:@"get"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypePermissions}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        "action": TNArchipelTypePermissionsGet,
        "permission_type": "user",
        "permission_target": aUser}];

    [_entity sendStanza:stanza andRegisterSelector:@selector(_didReceiveUserPermissions:) ofObject:self];
}

/*! compute the answer containing the user' permissions
    @param aStanza TNStropheStanza containing the answer
*/
- (void)_didReceiveUserPermissions:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"result")
    {
        var permissions = [aStanza childrenWithName:@"permission"];

        [_currentUserPermissions removeAllObjects];
        for (var i = 0; i < [permissions count]; i++)
        {
            var permission      = [permissions objectAtIndex:i],
                name            = [permission valueForAttribute:@"name"];

            [_currentUserPermissions addObject:name]
        }
        [self getPermissions];
    }
    else
    {
        [self handleIqErrorFromStanza:aStanza];
    }
}

/*! change the permissions
*/
- (void)changePermissionsState
{
    var stanza = [TNStropheStanza iqWithType:@"set"];

    [stanza addChildWithName:@"query" andAttributes:{"xmlns": TNArchipelTypePermissions}];
    [stanza addChildWithName:@"archipel" andAttributes:{
        @"action": TNArchipelTypePermissionsSet}];

    for (var i = 0; i < [_datasourcePermissions count]; i++)
    {
        var perm = [_datasourcePermissions objectAtIndex:i];
        [stanza addChildWithName:@"permission" andAttributes:{
            @"permission_target": [[[buttonUser selectedItem] objectValue] bare],
            @"permission_type": @"user",
            @"permission_name": [perm objectForKey:@"name"],
            @"permission_value": ([perm valueForKey:@"state"] === CPOnState),
        }];
        [stanza up];
    }

    [_entity sendStanza:stanza andRegisterSelector:@selector(_didChangePermissionsState:) ofObject:self];
}

/*! compute the answer containing the result of changing the permissions
    @param aStanza TNStropheStanza containing the answer
*/
- (void)_didChangePermissionsState:(TNStropheStanza)aStanza
{
    if ([aStanza type] == @"error")
        [self handleIqErrorFromStanza:aStanza];
}



#pragma mark -
#pragma mark Delegates

// put your delegates here

@end



