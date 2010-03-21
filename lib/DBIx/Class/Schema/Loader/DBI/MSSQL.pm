package DBIx::Class::Schema::Loader::DBI::MSSQL;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI::Sybase::Common';
use Carp::Clan qw/^DBIx::Class/;
use Class::C3;

our $VERSION = '0.05003';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::MSSQL - DBIx::Class::Schema::Loader::DBI MSSQL Implementation.

=head1 DESCRIPTION

Base driver for Microsoft SQL Server, used by
L<DBIx::Class::Schema::Loader::DBI::Sybase::Microsoft_SQL_Server> for support
via L<DBD::Sybase> and
L<DBIx::Class::Schema::Loader::DBI::ODBC::Microsoft_SQL_Server> for support via
L<DBD::ODBC>.

See L<DBIx::Class::Schema::Loader> and L<DBIx::Class::Schema::Loader::Base> for
usage information.

=cut

sub _tables_list {
    my $self = shift;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(<<'EOF');
select t.table_name
from information_schema.tables t
where t.table_schema = ?
EOF
    $sth->execute($self->db_schema);

    my @tables = map lc $_, map @$_, @{ $sth->fetchall_arrayref };

    return $self->_filter_tables(@tables);
}

sub _table_pk_info {
    my ($self, $table) = @_;
    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(qq{sp_pkeys '$table'});
    $sth->execute;

    my @keydata;

    while (my $row = $sth->fetchrow_hashref) {
        push @keydata, lc $row->{COLUMN_NAME};
    }

    return \@keydata;
}

sub _table_fk_info {
    my ($self, $table) = @_;

    my ($local_cols, $remote_cols, $remote_table, @rels);
    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(qq{sp_fkeys \@FKTABLE_NAME = '$table'});
    $sth->execute;

    while (my $row = $sth->fetchrow_hashref) {
        my $fk = $row->{FK_NAME};
        push @{$local_cols->{$fk}}, lc $row->{FKCOLUMN_NAME};
        push @{$remote_cols->{$fk}}, lc $row->{PKCOLUMN_NAME};
        $remote_table->{$fk} = $row->{PKTABLE_NAME};
    }

    foreach my $fk (keys %$remote_table) {
        push @rels, {
                      local_columns => \@{$local_cols->{$fk}},
                      remote_columns => \@{$remote_cols->{$fk}},
                      remote_table => $remote_table->{$fk},
                    };

    }
    return \@rels;
}

sub _table_uniq_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(qq{SELECT CCU.CONSTRAINT_NAME, CCU.COLUMN_NAME FROM INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE CCU
                               JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS TC ON (CCU.CONSTRAINT_NAME = TC.CONSTRAINT_NAME)
                               JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE KCU ON (CCU.CONSTRAINT_NAME = KCU.CONSTRAINT_NAME AND CCU.COLUMN_NAME = KCU.COLUMN_NAME)
                               WHERE CCU.TABLE_NAME = @{[ $dbh->quote($table) ]} AND CONSTRAINT_TYPE = 'UNIQUE' ORDER BY KCU.ORDINAL_POSITION});
    $sth->execute;
    my $constraints;
    while (my $row = $sth->fetchrow_hashref) {
        my $name = lc $row->{CONSTRAINT_NAME};
        my $col  = lc $row->{COLUMN_NAME};
        push @{$constraints->{$name}}, $col;
    }

    my @uniqs = map { [ $_ => $constraints->{$_} ] } keys %$constraints;
    return \@uniqs;
}

sub _columns_info_for {
    my $self    = shift;
    my ($table) = @_;

    my $result = $self->next::method(@_);

    while (my ($col, $info) = each %$result) {
        my $dbh = $self->schema->storage->dbh;
        my $sth = $dbh->prepare(qq{
            SELECT COLUMN_NAME 
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE COLUMNPROPERTY(object_id(@{[ $dbh->quote($table) ]}, 'U'), @{[ $dbh->quote($col) ]}, 'IsIdentity') = 1
              AND TABLE_NAME = @{[ $dbh->quote($table) ]} AND COLUMN_NAME = @{[ $dbh->quote($col) ]}
        });
        $sth->execute();

        if ($sth->fetchrow_array) {
            $info->{is_auto_increment} = 1;
            $info->{data_type} =~ s/\s*identity//i;
            delete $info->{size};
        }

# get default
        $sth = $dbh->prepare(qq{
            SELECT COLUMN_DEFAULT
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = @{[ $dbh->quote($table) ]} AND COLUMN_NAME = @{[ $dbh->quote($col) ]}
        });
        $sth->execute;
        my ($default) = $sth->fetchrow_array;

        if (defined $default) {
            # strip parens
            $default =~ s/^\( (.*) \)\z/$1/x;

            # Literal strings are in ''s, numbers are in ()s (in some versions of
            # MSSQL, in others they are unquoted) everything else is a function.
            $info->{default_value} =
                $default =~ /^['(] (.*) [)']\z/x ? $1 :
                    $default =~ /^\d/ ? $default : \$default;
        }
    }

    return $result;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader::DBI::Sybase::Microsoft_SQL_Server>,
L<DBIx::Class::Schema::Loader::DBI::ODBC::Microsoft_SQL_Server>,
L<DBIx::Class::Schema::Loader>, L<DBIx::Class::Schema::Loader::Base>,
L<DBIx::Class::Schema::Loader::DBI>

=head1 AUTHOR

See L<DBIx::Class::Schema::Loader/AUTHOR> and L<DBIx::Class::Schema::Loader/CONTRIBUTORS>.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
