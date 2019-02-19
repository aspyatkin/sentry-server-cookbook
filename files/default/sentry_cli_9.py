# Sentry CLI script
# Compatible with Sentry 9.x
# Copyright (c) 2019 Alexander Pyatkin

import os
import sys
import click

from sentry.utils.runner import configure
configure()

from sentry.models import (
    User,
    Organization,
    OrganizationMember,
    Team,
    OrganizationMemberTeam,
    Project,
    ProjectTeam
)


def sentry_find_user(username):
    records = User.objects.filter(username=username)
    if len(records) > 0:
        return records[0]
    return None


def sentry_create_user(username, password, admin=False):
    model = sentry_find_user(username)
    existing = model is not None
    if not existing:
        model = User()
        model.username = username
        model.is_superuser = admin
        model.set_password(password)
        model.save()

    return model, existing


def sentry_find_organization(name):
    records = Organization.objects.filter(name=name)
    if len(records) > 0:
        return records[0]
    return None


def sentry_create_organization(name):
    model = sentry_find_organization(name)
    existing = model is not None
    if not existing:
        model = Organization()
        model.name = name
        model.save()

    return model, existing


def sentry_find_organization_member(organization, user):
    records = OrganizationMember.objects.filter(
        user_id=user.id,
        organization_id=organization.id
    )
    if len(records) > 0:
        return records[0]
    return None


def sentry_update_organization_member(organization, user, role):
    model = sentry_find_organization_member(organization, user)
    existing = model is not None
    if not existing:
        model = OrganizationMember()
        model.user = user
        model.organization = organization
        model.role = role
        model.save()

    return model, existing


def sentry_find_team(organization, name):
    records = Team.objects.filter(name=name, organization_id=organization.id)
    if len(records) > 0:
        return records[0]
    return None


def sentry_create_team(organization, name):
    model = sentry_find_team(organization, name)
    existing = model is not None
    if not existing:
        model = Team()
        model.name = name
        model.organization = organization
        model.save()

    return model, existing


def sentry_find_team_member(team, organization_member):
    records = OrganizationMemberTeam.objects.filter(
        organizationmember_id=organization_member.id,
        team_id=team.id
    )
    if len(records) > 0:
        return records[0]
    return None


def sentry_update_team_member(team, organization_member):
    model = sentry_find_team_member(team, organization_member)
    existing = model is not None
    if not existing:
        model = OrganizationMemberTeam()
        model.organizationmember = organization_member
        model.team = team
        model.save()

    return model, existing


def sentry_find_project(team, name):
    records = Project.objects.filter(
        name=name,
        teams__id=team.id,
        organization_id=team.organization.id
    )
    if len(records) > 0:
        return records[0]
    return None

def sentry_create_project(team, name):
    model = sentry_find_project(team, name)
    existing = model is not None
    if not existing:
        model = Project()
        model.name = name
        model.organization = team.organization
        model.save()
        model2 = ProjectTeam()
        model2.project = model
        model2.team = team
        model2.save()

    return model, existing


@click.group()
def cli_main():
    pass


@cli_main.group('create')
def cli_create():
    pass


@cli_create.command('user')
@click.argument('username')
@click.argument('password_env')
def cli_create_user(username, password_env):
    password = os.getenv(password_env)
    if password is None:
        click.secho('User password not specified', fg='red')
        sys.exit(21)
    user, existing = sentry_create_user(username, password, False)
    if existing:
        click.secho('User <{0}> already exists'.format(username), fg='yellow')
    else:
        click.secho('Created user <{0}>'.format(username), fg='green')


@cli_create.command('superuser')
@click.argument('username')
@click.argument('password_env')
def cli_create_superuser(username, password_env):
    password = os.getenv(password_env)
    if password is None:
        click.secho('User password not specified', fg='red')
        sys.exit(21)
    user, existing = sentry_create_user(username, password, True)
    if existing:
        click.secho('Superuser <{0}> already exists'.format(username), fg='yellow')
    else:
        click.secho('Created superuser <{0}>'.format(username), fg='green')


@cli_create.command('organization')
@click.argument('name')
def cli_create_organization(name):
    organization, existing = sentry_create_organization(name)
    if existing:
        click.secho('Organization <{0}> already exists'.format(name), fg='yellow')
    else:
        click.secho('Created organization <{0}>'.format(name), fg='green')


@cli_create.command('team')
@click.argument('organization_name')
@click.argument('name')
def cli_create_team(organization_name, name):
    organization = sentry_find_organization(organization_name)
    if organization is None:
        click.secho('Organization <{0}> does not exist'.format(organization_name), fg='red')
        sys.exit(25)
    team, existing = sentry_create_team(organization, name)
    if existing:
        click.secho('Team <{0}> in organization <{1}> already exists'.format(name, organization_name), fg='yellow')
    else:
        click.secho('Created team <{0}> in organization <{1}>'.format(name, organization_name), fg='green')


@cli_create.command('project')
@click.argument('organization_name')
@click.argument('team_name')
@click.argument('name')
def cli_create_project(organization_name, team_name, name):
    organization = sentry_find_organization(organization_name)
    if organization is None:
        click.secho('Organization <{0}> does not exist'.format(organization_name), fg='red')
        sys.exit(30)
    team = sentry_find_team(organization, team_name)
    if team is None:
        click.secho('Team <{0}> does not exist in organization <{1}>'.format(team_name, organization_name), fg='red')
        sys.exit(31)
    project, existing = sentry_create_project(team, name)
    if existing:
        click.secho('Team <{0}> project <{1}> in organization <{2}> already exists'.format(team_name, name, organization_name), fg='yellow')
    else:
        click.secho('Created team <{0}> project <{1}> in organization <{2}>'.format(team_name, name, organization_name), fg='green')


@cli_main.group('update')
def cli_update():
    pass


@cli_update.command('organization')
@click.argument('name')
@click.option('--owner', default=None)
@click.option('--member', default=None)
def cli_update_organization(name, owner, member):
    organization = sentry_find_organization(name)
    if organization is None:
        click.secho('Organization <{0}> does not exist'.format(name), fg='red')
        sys.exit(22)
    if owner is not None:
        user = sentry_find_user(owner)
        if user is None:
            click.secho('User <{0}> does not exist'.format(owner), fg='red')
            sys.exit(23)
        organization_member, existing = sentry_update_organization_member(
            organization,
            user,
            'owner'
        )
        if existing:
            click.secho('Organization <{0}> member <{1}> already exists'.format(name, owner), fg='yellow')
        else:
            click.secho('Created organization <{0}> member <{1}>'.format(name, owner), fg='green')
    elif member is not None:
        user = sentry_find_user(member)
        if user is None:
            click.secho('User <{0}> does not exist'.format(member), fg='red')
            sys.exit(24)
        organization_member, existing = sentry_update_organization_member(
            organization,
            user,
            'member'
        )
        if existing:
            click.secho('Organization <{0}> member <{1}> already exists'.format(name, member), fg='yellow')
        else:
            click.secho('Created organization <{0}> member <{1}>'.format(name, member), fg='green')
    else:
        click.secho('Nothing to update', fg='yellow')


@cli_update.command('team')
@click.argument('organization_name')
@click.argument('team_name')
@click.option('--member', default=None)
def cli_update_team(organization_name, team_name, member):
    organization = sentry_find_organization(organization_name)
    if organization is None:
        click.secho('Organization <{0}> does not exist'.format(organization_name), fg='red')
        sys.exit(26)
    team = sentry_find_team(organization, team_name)
    if team is None:
        click.secho('Team <{0}> does not exist in organization <{1}>'.format(team_name, organization_name), fg='red')
        sys.exit(27)
    if member is not None:
        user = sentry_find_user(member)
        if user is None:
            click.secho('User <{0}> does not exist'.format(member), fg='red')
            sys.exit(28)
        organization_member = sentry_find_organization_member(organization, user)
        if organization_member is None:
            click.secho('User <{0}> does not belong to organization <{1}>'.format(member, organization_name), fg='red')
            sys.exit(29)
        team_member, existing = sentry_update_team_member(team, organization_member)
        if existing:
            click.secho('Organization <{0}> team <{1}> member <{2}> already exists'.format(organization_name, team_name, member), fg='yellow')
        else:
            click.secho('Created organization <{0}> team <{1}> member <{2}>'.format(organization_name, team_name, member), fg='green')
    else:
        click.secho('Nothing to update', fg='yellow')


if __name__ == '__main__':
    cli_main()
