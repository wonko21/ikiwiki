#!/usr/bin/perl
package IkiWiki::Plugin::remove;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "formbuilder_setup", id => "remove", call => \&formbuilder_setup);
	hook(type => "formbuilder", id => "remove", call => \&formbuilder);
	hook(type => "sessioncgi", id => "remove", call => \&sessioncgi);

} # }}}

sub formbuilder_setup (@) { #{{{
	my %params=@_;
	my $form=$params{form};
	my $q=$params{cgi};

	if (defined $form->field("do") && $form->field("do") eq "edit") {
		# Removal button for the page, and also for attachments.
		push @{$params{buttons}}, "Remove";
		$form->tmpl_param("field-remove" => '<input name="_submit" type="submit" value="Remove Attachments" />');
	}
} #}}}

sub confirmation_form ($$) { #{{{ 
	my $q=shift;
	my $session=shift;

	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my @fields=qw(do page);
	my $f = CGI::FormBuilder->new(
		name => "remove",
		header => 0,
		charset => "utf-8",
		method => 'POST',
		javascript => 0,
		params => $q,
		action => $config{cgiurl},
		stylesheet => IkiWiki::baseurl()."style.css",
		fields => \@fields,
	);
	
	$f->field(name => "do", type => "hidden", value => "remove", force => 1);

	return $f, ["Remove", "Cancel"];
} #}}}

sub removal_confirm ($$@) {
	my $q=shift;
	my $session=shift;
	my $attachment=shift;
	my @pages=@_;

   	# Save current form state to allow returning to it later
	# without losing any edits.
	# (But don't save what button was submitted, to avoid
	# looping back to here.)
	# Note: "_submit" is CGI::FormBuilder internals.
	$q->param(-name => "_submit", -value => "");
	$session->param(postremove => scalar $q->Vars);
	IkiWiki::cgi_savesession($session);
	
	my ($f, $buttons)=confirmation_form($q, $session);
	$f->title(sprintf(gettext("confirm removal of %s"),
		join(", ", map { IkiWiki::pagetitle($_) } @pages)));
	$f->field(name => "page", type => "hidden", value => \@pages, force => 1);
	if (defined $attachment) {
		$f->field(name => "attachment", type => "hidden",
			value => $attachment, force => 1);
	}

	IkiWiki::showform($f, $buttons, $session, $q);
	exit 0;
}

sub postremove ($) {
	my $session=shift;

	# Load saved form state and return to edit form.
	my $postremove=CGI->new($session->param("postremove"));
	$session->clear("postremove");
	IkiWiki::cgi_savesession($session);
	IkiWiki::cgi($postremove, $session);
}

sub formbuilder (@) { #{{{
	my %params=@_;
	my $form=$params{form};

	if (defined $form->field("do") && $form->field("do") eq "edit") {
		my $q=$params{cgi};
		my $session=$params{session};

		if ($form->submitted eq "Remove") {
			removal_confirm($q, $session, 0, $form->field("page"));
		}
		elsif ($form->submitted eq "Remove Attachments") {
			removal_confirm($q, $session, 1, $q->param("attachment_select"));
		}
	}
} #}}}

sub sessioncgi ($$) { #{{{
        my $q=shift;

	if ($q->param("do") eq 'remove') {
        	my $session=shift;
		my ($form, $buttons)=confirmation_form($q, $session);
		IkiWiki::decode_form_utf8($form);

		if ($form->submitted eq 'Cancel') {
			postremove($session);
		}
		elsif ($form->submitted eq 'Remove' && $form->validate) {
			my @pages=$q->param("page");
			my @files = map { $pagesources{$_} } @pages;
	
			# Validate removal by checking that the page exists,
			# and that the user is allowed to edit(/remove) it.
			my @files;
			foreach my $page (@pages) {
				if (! exists $pagesources{$page}) {
					error(sprintf(gettext("%s does not exist"),
					htmllink("", "", $page, noimageinline => 1)));
				}
				IkiWiki::check_canedit($page, $q, $session);

				my $file=$pagesources{$_};
				if (! -e "$config{srcdir}/$file") {
					error(sprintf(gettext("%s is not in the srcdir, so it cannot be deleted"), $file));
				}
				elsif (! -f "$config{srcdir}/$file") {
					error(sprintf(gettext("%s is not a file"), $file));
				}
				push @files, $file;
			}

			# Do removal, and update the wiki.
			require IkiWiki::Render;
			if ($config{rcs}) {
				IkiWiki::disable_commit_hook();
				foreach my $file (@files) {
					my $token=IkiWiki::rcs_prepedit($file);
					IkiWiki::rcs_remove($file);
					IkiWiki::rcs_commit($file, gettext("removed"),
						$token, $session->param("name"), $ENV{REMOTE_ADDR});
				}
				IkiWiki::enable_commit_hook();
				IkiWiki::rcs_update();
			}
			else {
				foreach my $file (@files) {
					IkiWiki::prune("$config{srcdir}/$file");
				}
			}
			foreach my $file (@files) {
				delete $IkiWiki::pagecase{$file};
				print STDERR "delete $file\n";
				delete $IkiWiki::links{$file};
			}
			IkiWiki::refresh();
			IkiWiki::saveindex();

			if ($q->param("attachment")) {
				# Attachments were deleted, so redirect
				# back to the edit form.
				postremove($session);
			}
			else {
				# The page is gone, so redirect to parent
				# of the page.
				my $parent=IkiWiki::dirname($pages[0]);
				if (! exists $pagesources{$parent}) {
					$parent="index";
				}
				IkiWiki::redirect($q, $config{url}."/".htmlpage($parent));
			}
		}
		else {
			IkiWiki::showform($form, $buttons, $session, $q);
		}

		exit 0;
	}
}

1
